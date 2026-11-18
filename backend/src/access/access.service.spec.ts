import { AbilityBuilder, createMongoAbility, MongoQuery } from '@casl/ability';
import { readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { Role } from '@prisma/client';
import { AccessService, Action, Actor, AppAbility, canDo, defineAbilityFor, effectivePermissions, hasPermission, roleChangeError, SubjectName } from './access.service';
import { defaultPermissionsFor, describeEffect, PermissionKey } from './permissions';

/** The hard-coded rules as they were before permissions moved into the database. */
function legacyAbilityFor(a: Actor): AppAbility {
  const { can, cannot, build } = new AbilityBuilder<AppAbility>(createMongoAbility);
  const projectIds = a.projects.map((p) => p.projectId);
  const leadProjectIds = a.projects.filter((p) => p.role !== 'MEMBER').map((p) => p.projectId);
  can('read', 'Employee');
  can('update', 'Employee', { id: a.id });
  can('readSensitive', 'Employee', { id: a.id });
  can(['read', 'create', 'cancel'], 'LeaveRequest', { employeeId: a.id });
  can(['read', 'create'], 'Attendance', { employeeId: a.id });
  can(['read', 'book'], 'MealBooking', { employeeId: a.id });
  can('read', ['Policy', 'LeaveType', 'Holiday']);
  can('ack', 'PolicyVersion');
  if (a.managerOf.length) {
    can('read', ['LeaveRequest', 'Attendance'], { employeeId: { $in: a.managerOf } });
    can('approve', 'LeaveRequest', { employeeId: { $in: a.managerOf }, status: 'PENDING_MANAGER' });
  }
  can('read', 'Project', { id: { $in: projectIds } });
  can(['create', 'update'], 'Task', { projectId: { $in: projectIds } });
  can(['read', 'upload'], 'Folder', { projectId: { $in: projectIds }, sensitivity: 'NORMAL' });
  can(['read', 'upload'], 'Folder', { projectId: { $in: leadProjectIds } });
  can('update', 'Project', { id: { $in: leadProjectIds } });
  if (['HR', 'HR_ADMIN'].includes(a.role)) {
    const scope = (a.role === 'HR_ADMIN' ? {} : { locationId: a.locationId }) as MongoQuery;
    can(['create', 'update', 'readSensitive'], 'Employee', scope);
    can('read', ['LeaveRequest', 'Attendance'], a.role === 'HR_ADMIN' ? {} : { employeeLocationId: a.locationId });
    can('approve', 'LeaveRequest', { status: 'PENDING_HR', ...(a.role === 'HR_ADMIN' ? {} : { employeeLocationId: a.locationId }) });
    can('manage', ['LeaveType', 'Holiday', 'Policy', 'PolicyVersion', 'Invite']);
    can('read', 'MealReport');
  }
  if (a.role === 'FINANCE') {
    can('readSensitive', 'Employee');
    can('read', 'MealReport');
  }
  if (a.role === 'SUPER_ADMIN') can('manage', 'all');
  cannot('approve', 'LeaveRequest', { employeeId: a.id });
  return build();
}
/** Projects used to bypass CASL for these roles (ProjectsService.canSeeAll). */
const legacySeesAllProjects = (role: Role) => role === 'SUPER_ADMIN' || role === 'HR_ADMIN';

const ROLES: Role[] = ['EMPLOYEE', 'HR', 'HR_ADMIN', 'FINANCE', 'SUPER_ADMIN'];
const ACTIONS: Action[] = ['manage', 'read', 'create', 'update', 'delete', 'approve', 'cancel', 'readSensitive', 'ack', 'book', 'upload'];

function actor(role: Role, opts: { manager?: boolean; permissions?: PermissionKey[] } = {}): Actor {
  return {
    id: 'me',
    role,
    locationId: 'L1',
    departmentId: null,
    managerOf: opts.manager ? ['report'] : [],
    projects: [{ projectId: 'p1', role: 'MEMBER' }, { projectId: 'p2', role: 'LEAD' }],
    permissions: opts.permissions ?? effectivePermissions(role, defaultPermissionsFor(role)),
  };
}

const people = ['me', 'report', 'other'];
const locations = ['L1', 'L2', null];
const statuses = ['PENDING_MANAGER', 'PENDING_HR', 'APPROVED'];
const projects = ['p1', 'p2', 'p3'];

/** Records with every attribute combination the rules look at, plus the bare type. */
const RECORDS: [SubjectName, Record<string, unknown>][] = [
  ...(['LeaveType', 'Holiday', 'MealReport', 'Policy', 'PolicyVersion', 'Invite', 'OfficeNetwork', 'AuditLog', 'Employee', 'LeaveRequest', 'Attendance', 'MealBooking', 'Project', 'Task', 'Folder'] as SubjectName[])
    .map((t): [SubjectName, Record<string, unknown>] => [t, {}]),
  ...people.flatMap((id) => locations.map((locationId): [SubjectName, Record<string, unknown>] => ['Employee', { id, locationId }])),
  ...people.flatMap((employeeId) => locations.flatMap((employeeLocationId) => statuses.map((status): [SubjectName, Record<string, unknown>] => ['LeaveRequest', { employeeId, employeeLocationId, status }]))),
  ...people.flatMap((employeeId) => locations.map((employeeLocationId): [SubjectName, Record<string, unknown>] => ['Attendance', { employeeId, employeeLocationId }])),
  ...people.map((employeeId): [SubjectName, Record<string, unknown>] => ['MealBooking', { employeeId }]),
  ...projects.map((id): [SubjectName, Record<string, unknown>] => ['Project', { id }]),
  ...projects.map((projectId): [SubjectName, Record<string, unknown>] => ['Task', { projectId }]),
  ...projects.flatMap((projectId) => ['NORMAL', 'RESTRICTED'].map((sensitivity): [SubjectName, Record<string, unknown>] => ['Folder', { projectId, sensitivity }])),
];

describe('defineAbilityFor', () => {
  describe('with the default grants', () => {
    for (const role of ROLES) {
      for (const manager of [false, true]) {
        it(`allows exactly what the old rules allowed for ${role}${manager ? ' (manager)' : ''}`, () => {
          const a = actor(role, { manager });
          const now = defineAbilityFor(a);
          const before = legacyAbilityFor(a);
          const diffs: string[] = [];
          for (const [type, record] of RECORDS) {
            for (const action of ACTIONS) {
              const projectBypass = legacySeesAllProjects(role) && ['Project', 'Task', 'Folder'].includes(type);
              const expected = canDo(before, action, type, record) || projectBypass;
              if (canDo(now, action, type, record) !== expected) diffs.push(`${action} ${type} ${JSON.stringify(record)}: expected ${expected}`);
            }
          }
          expect(diffs).toEqual([]);
          expect(hasPermission(a, 'projects.manageAll')).toBe(legacySeesAllProjects(role));
        });
      }
    }
  });

  it('migration seeds exactly the default grants', () => {
    const dir = path.join(__dirname, '../../prisma/migrations');
    const sql = readdirSync(dir).filter((d) => d.endsWith('_role_permissions')).map((d) => readFileSync(path.join(dir, d, 'migration.sql'), 'utf8')).join('');
    const seeded = [...sql.matchAll(/\('(\w+)', '([\w.]+)'\)/g)].map((m) => `${m[1]}:${m[2]}`).sort();
    const defaults = ROLES.flatMap((r) => (r === 'SUPER_ADMIN' ? [] : defaultPermissionsFor(r).map((k) => `${r}:${k}`))).sort();
    expect(seeded).toEqual(defaults);
  });

  it('turning a permission off for a role removes that access', () => {
    const without = (role: Role, k: PermissionKey) => actor(role, { permissions: defaultPermissionsFor(role).filter((p) => p !== k) });
    expect(canDo(defineAbilityFor(actor('FINANCE')), 'read', 'MealReport')).toBe(true);
    expect(canDo(defineAbilityFor(without('FINANCE', 'meals.viewReport')), 'read', 'MealReport')).toBe(false);

    const pendingHr = { employeeId: 'other', employeeLocationId: 'L1', status: 'PENDING_HR' };
    expect(canDo(defineAbilityFor(actor('HR')), 'approve', 'LeaveRequest', pendingHr)).toBe(true);
    const hr = defineAbilityFor(without('HR', 'leave.approve'));
    expect(canDo(hr, 'approve', 'LeaveRequest', pendingHr)).toBe(false);
    // Everything else HR had stays.
    expect(canDo(hr, 'manage', 'Policy')).toBe(true);

    expect(hasPermission(without('HR_ADMIN', 'projects.manageAll'), 'projects.manageAll')).toBe(false);
  });

  it('personal overrides add or remove one permission', () => {
    const revoked = effectivePermissions('HR', defaultPermissionsFor('HR'), [['employees.manage', false]]);
    expect(canDo(defineAbilityFor(actor('HR', { permissions: revoked })), 'create', 'Employee', { locationId: 'L1' })).toBe(false);

    // An employee given a people permission only reaches their own location.
    const granted = effectivePermissions('EMPLOYEE', [], [['employees.viewSensitive', true]]);
    const emp = defineAbilityFor(actor('EMPLOYEE', { permissions: granted }));
    expect(canDo(emp, 'readSensitive', 'Employee', { id: 'other', locationId: 'L1' })).toBe(true);
    expect(canDo(emp, 'readSensitive', 'Employee', { id: 'other', locationId: 'L2' })).toBe(false);
  });

  it('super admins keep full access with no grants, and nobody approves their own leave', () => {
    const admin = defineAbilityFor(actor('SUPER_ADMIN', { permissions: [] }));
    expect(canDo(admin, 'manage', 'AuditLog')).toBe(true);
    expect(canDo(admin, 'approve', 'LeaveRequest', { employeeId: 'other', status: 'PENDING_HR' })).toBe(true);
    expect(canDo(admin, 'approve', 'LeaveRequest', { employeeId: 'me', status: 'PENDING_HR' })).toBe(false);
    expect(effectivePermissions('SUPER_ADMIN', [], [['offices.manage', false]])).toContain('offices.manage');

    const hr = defineAbilityFor(actor('HR'));
    expect(canDo(hr, 'approve', 'LeaveRequest', { employeeId: 'me', employeeLocationId: 'L1', status: 'PENDING_HR' })).toBe(false);
  });
});

describe('AccessService grants cache', () => {
  function service(rows: { role: Role; permission: string }[]) {
    const prisma = {
      rolePermission: { findMany: jest.fn(() => Promise.resolve(rows)) },
      permissionOverride: { findMany: jest.fn(() => Promise.resolve([{ employeeId: 'e1', permission: 'offices.manage', granted: true }])) },
    };
    return { svc: new AccessService(prisma as never, { log: jest.fn() } as never), prisma };
  }

  it('reads grants once until invalidated, ignoring unknown keys', async () => {
    const rows: { role: Role; permission: string }[] = [{ role: 'FINANCE', permission: 'meals.viewReport' }, { role: 'FINANCE', permission: 'gone.permission' }];
    const { svc, prisma } = service(rows);
    expect(await svc.permissionsOf('e1', 'FINANCE')).toEqual(['offices.manage', 'meals.viewReport']);
    rows.length = 0;
    expect(await svc.permissionsOf('e2', 'FINANCE')).toEqual(['meals.viewReport']);
    expect(prisma.rolePermission.findMany).toHaveBeenCalledTimes(1);
    svc.invalidate();
    expect(await svc.permissionsOf('e2', 'FINANCE')).toEqual([]);
    expect(prisma.rolePermission.findMany).toHaveBeenCalledTimes(2);
  });
});

describe('roleChangeError', () => {
  const superAdmin = { id: 'boss', role: 'SUPER_ADMIN' as Role };

  it('lets only a super admin change roles', () => {
    expect(roleChangeError(superAdmin, { id: 'x', role: 'EMPLOYEE' }, 'HR', 1)).toBeNull();
    expect(roleChangeError({ id: 'hra', role: 'HR_ADMIN' }, { id: 'x', role: 'EMPLOYEE' }, 'SUPER_ADMIN', 1)).toMatch(/Only a super admin/);
    expect(roleChangeError({ id: 'hra', role: 'HR_ADMIN' }, { id: 'x', role: 'EMPLOYEE' }, 'HR', 1)).toMatch(/Only a super admin/);
    // Saving a form with the role unchanged is fine for anyone.
    expect(roleChangeError({ id: 'hra', role: 'HR_ADMIN' }, { id: 'x', role: 'HR' }, 'HR', 1)).toBeNull();
  });

  it('blocks changing your own role and demoting the last super admin', () => {
    expect(roleChangeError(superAdmin, { id: 'boss', role: 'SUPER_ADMIN' }, 'EMPLOYEE', 3)).toMatch(/your own role/);
    expect(roleChangeError(superAdmin, { id: 'other', role: 'SUPER_ADMIN' }, 'HR', 0)).toMatch(/last super admin/);
    expect(roleChangeError(superAdmin, { id: 'other', role: 'SUPER_ADMIN' }, 'HR', 1)).toBeNull();
  });
});

describe('describeEffect', () => {
  it('explains the scope for the role', () => {
    expect(describeEffect('leave.viewAll', 'EMPLOYEE', false)).toMatch(/their own leave/);
    expect(describeEffect('leave.viewAll', 'HR', true)).toMatch(/at their location/);
    expect(describeEffect('leave.viewAll', 'HR_ADMIN', true)).toBe('Sees everyone’s leave and attendance.');
  });
});
