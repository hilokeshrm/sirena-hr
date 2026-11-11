import { AbilityBuilder, createMongoAbility, MongoAbility, MongoQuery, subject as asSubject } from '@casl/ability';
import { BadRequestException, ForbiddenException, Global, Injectable, Module, NotFoundException, UnauthorizedException } from '@nestjs/common';
import { ProjectRole, Role } from '@prisma/client';
import { AuditService } from '../common/audit.service';
import { PrismaService } from '../prisma/prisma.service';
import { isPermissionKey, LOCATION_SCOPED_ROLES, PERMISSION_KEYS, PermissionKey } from './permissions';

/** Everything the access rules know about the signed-in person. */
export interface Actor {
  id: string;
  role: Role;
  locationId: string | null;
  departmentId: string | null;
  /** Everyone below this person in the reporting tree. */
  managerOf: string[];
  projects: { projectId: string; role: ProjectRole }[];
  /** Permissions held through the person's role and personal overrides. */
  permissions: PermissionKey[];
  /** Signed in with a temporary password that must be changed before anything else. */
  mustChangePassword?: boolean;
}

export type Action =
  | 'manage' | 'read' | 'create' | 'update' | 'delete'
  | 'approve' | 'cancel' | 'readSensitive' | 'ack' | 'book' | 'upload';

export type SubjectName =
  | 'Employee' | 'LeaveRequest' | 'LeaveType' | 'Holiday' | 'Attendance' | 'MealBooking' | 'MealReport'
  | 'Project' | 'Task' | 'Folder' | 'Policy' | 'PolicyVersion' | 'Invite' | 'OfficeNetwork' | 'AuditLog' | 'all';

export type AppAbility = MongoAbility<[Action, SubjectName | Record<string, unknown>]>;

/**
 * Attribute-based access rules. Each rule reads attributes of the person
 * (role, location, reports, projects, granted permissions) and of the record
 * (owner, status, project, sensitivity). Anything not allowed here is denied.
 * Which permissions a role holds is data (RolePermission / PermissionOverride);
 * what each permission allows, and how far it reaches, is defined here.
 */
export function defineAbilityFor(a: Actor): AppAbility {
  const { can, cannot, build } = new AbilityBuilder<AppAbility>(createMongoAbility);
  const projectIds = a.projects.map((p) => p.projectId);
  const leadProjectIds = a.projects.filter((p) => p.role !== 'MEMBER').map((p) => p.projectId);
  const has = (k: PermissionKey) => a.permissions.includes(k);

  // ── Everyone ──
  can('read', 'Employee'); // directory fields only; services strip restricted fields
  can('update', 'Employee', { id: a.id }); // own contact details only
  can('readSensitive', 'Employee', { id: a.id });
  can(['read', 'create', 'cancel'], 'LeaveRequest', { employeeId: a.id });
  can(['read', 'create'], 'Attendance', { employeeId: a.id });
  can(['read', 'book'], 'MealBooking', { employeeId: a.id });
  can('read', ['Policy', 'LeaveType', 'Holiday']);
  can('ack', 'PolicyVersion');

  // ── Managers: anyone who has reports ──
  if (a.managerOf.length) {
    can('read', ['LeaveRequest', 'Attendance'], { employeeId: { $in: a.managerOf } });
    can('approve', 'LeaveRequest', { employeeId: { $in: a.managerOf }, status: 'PENDING_MANAGER' });
  }

  // ── Projects: membership and project role ──
  can('read', 'Project', { id: { $in: projectIds } });
  can(['create', 'update'], 'Task', { projectId: { $in: projectIds } });
  can(['read', 'upload'], 'Folder', { projectId: { $in: projectIds }, sensitivity: 'NORMAL' });
  can(['read', 'upload'], 'Folder', { projectId: { $in: leadProjectIds } });
  can('update', 'Project', { id: { $in: leadProjectIds } });

  // ── Granted permissions. HR (and employees given one) reach their own location only. ──
  const local = LOCATION_SCOPED_ROLES.includes(a.role);
  const scope = (local ? { locationId: a.locationId } : {}) as MongoQuery;
  const employeeScope = (local ? { employeeLocationId: a.locationId } : {}) as MongoQuery;
  if (has('employees.viewSensitive')) can('readSensitive', 'Employee', scope);
  if (has('employees.manage')) can(['create', 'update'], 'Employee', scope);
  if (has('invites.send')) can('manage', 'Invite');
  if (has('leave.viewAll')) can('read', ['LeaveRequest', 'Attendance'], employeeScope);
  if (has('leave.approve')) can('approve', 'LeaveRequest', { status: 'PENDING_HR', ...employeeScope });
  if (has('leave.manageTypes')) can('manage', 'LeaveType');
  if (has('holidays.manage')) can('manage', 'Holiday');
  if (has('offices.manage')) can('manage', 'OfficeNetwork');
  if (has('policies.manage')) can('manage', ['Policy', 'PolicyVersion']);
  if (has('meals.viewReport')) can('read', 'MealReport');
  if (has('projects.manageAll')) can('manage', ['Project', 'Task', 'Folder']);
  if (has('audit.view')) can('read', 'AuditLog');

  // Super admins always keep full access, whatever the permission table says.
  if (a.role === 'SUPER_ADMIN') can('manage', 'all');

  // Nobody approves their own leave — this overrides every rule above.
  cannot('approve', 'LeaveRequest', { employeeId: a.id });

  return build();
}

/** Role grants plus one person's overrides → the permissions that person holds. */
export function effectivePermissions(role: Role, roleGrants: Iterable<PermissionKey>, overrides: Iterable<[PermissionKey, boolean]> = []): PermissionKey[] {
  if (role === 'SUPER_ADMIN') return [...PERMISSION_KEYS];
  const held = new Set(roleGrants);
  for (const [k, granted] of overrides) {
    if (granted) held.add(k);
    else held.delete(k);
  }
  return PERMISSION_KEYS.filter((k) => held.has(k));
}

/** True for super admins and anyone holding the permission. */
export function hasPermission(a: Actor, k: PermissionKey) {
  return a.role === 'SUPER_ADMIN' || a.permissions.includes(k);
}

/**
 * Why `actor` may not move `target` from its role to `next`, or null if they may.
 * Only super admins change roles; nobody changes their own super-admin access;
 * the last active super admin keeps the role.
 */
export function roleChangeError(actor: Pick<Actor, 'id' | 'role'>, target: { id: string; role: Role }, next: Role, otherActiveSuperAdmins: number): string | null {
  if (target.role === next) return null;
  if (actor.role !== 'SUPER_ADMIN') return 'Only a super admin can change roles';
  if (target.id === actor.id) return 'You can’t change your own role';
  if (target.role === 'SUPER_ADMIN' && otherActiveSuperAdmins === 0) return 'This is the last super admin. Make someone else super admin first.';
  return null;
}

interface Grants {
  roles: Map<Role, Set<PermissionKey>>;
  overrides: Map<string, [PermissionKey, boolean][]>;
}

// Grants change rarely; reload at least this often in case another process changed them.
const GRANTS_TTL_MS = 60_000;

@Injectable()
export class AccessService {
  private grants: { at: number; value: Promise<Grants> } | null = null;

  constructor(private prisma: PrismaService, private audit: AuditService) {}

  /** Who holds which permission, cached; call `invalidate()` after changing it. */
  loadGrants(): Promise<Grants> {
    if (this.grants && Date.now() - this.grants.at < GRANTS_TTL_MS) return this.grants.value;
    const value = (async () => {
      const [roleRows, overrideRows] = await Promise.all([this.prisma.rolePermission.findMany(), this.prisma.permissionOverride.findMany()]);
      const roles = new Map<Role, Set<PermissionKey>>();
      for (const r of roleRows) if (isPermissionKey(r.permission)) roles.set(r.role, (roles.get(r.role) ?? new Set()).add(r.permission));
      const overrides = new Map<string, [PermissionKey, boolean][]>();
      for (const o of overrideRows) {
        if (isPermissionKey(o.permission)) overrides.set(o.employeeId, [...(overrides.get(o.employeeId) ?? []), [o.permission, o.granted]]);
      }
      return { roles, overrides };
    })();
    this.grants = { at: Date.now(), value };
    value.catch(() => (this.grants = null));
    return value;
  }

  invalidate() {
    this.grants = null;
  }

  /** Throws unless `actor` may give `targetId` the role `next` (see roleChangeError). */
  async assertRoleChange(actor: Actor, targetId: string, next: Role) {
    const target = await this.prisma.employee.findUnique({ where: { id: targetId }, select: { id: true, role: true } });
    if (!target) throw new NotFoundException();
    const others = await this.prisma.employee.count({ where: { role: 'SUPER_ADMIN', status: { not: 'EXITED' }, id: { not: targetId } } });
    const error = roleChangeError(actor, target, next, others);
    if (error) throw (actor.role === 'SUPER_ADMIN' ? new BadRequestException(error) : new ForbiddenException(error));
    return target;
  }

  /** Records a role change. Super admins have everything, so their personal overrides are dropped. */
  async roleChanged(actor: Actor, employeeId: string, from: Role, to: Role) {
    if (from === to) return;
    const dropped = to === 'SUPER_ADMIN' ? (await this.prisma.permissionOverride.deleteMany({ where: { employeeId } })).count : 0;
    // Their open sessions end, so the app reloads what they may see.
    await this.revokeSessions(employeeId);
    this.invalidate();
    await this.audit.log(actor.id, 'change-role', 'Employee', employeeId, { from, to, ...(dropped ? { droppedOverrides: dropped } : {}) });
  }

  async permissionsOf(employeeId: string, role: Role) {
    const g = await this.loadGrants();
    return effectivePermissions(role, g.roles.get(role) ?? [], g.overrides.get(employeeId) ?? []);
  }

  /** Ends every session issued to this person so far (password change, role change). */
  async revokeSessions(employeeId: string) {
    await this.prisma.employee.update({ where: { id: employeeId }, data: { tokensValidFrom: sessionCutoff() } });
  }

  /** The person behind a token. `issuedAt` is the token's `iat` (seconds); tokens older than a revocation are refused. */
  async loadActor(employeeId: string, issuedAt?: number): Promise<Actor> {
    const me = await this.prisma.employee.findUnique({
      where: { id: employeeId },
      select: {
        id: true, role: true, status: true, locationId: true, departmentId: true, mustChangePassword: true, tokensValidFrom: true,
        memberships: { select: { projectId: true, role: true } },
      },
    });
    if (!me || me.status === 'EXITED') throw new UnauthorizedException();
    if (!tokenStillValid(issuedAt, me.tokensValidFrom)) throw new UnauthorizedException();

    // Walk the reporting tree (org is small, so one query is fine).
    const all = await this.prisma.employee.findMany({ where: { status: { not: 'EXITED' } }, select: { id: true, managerId: true } });
    const children = new Map<string, string[]>();
    for (const e of all) if (e.managerId) children.set(e.managerId, [...(children.get(e.managerId) ?? []), e.id]);
    const managerOf: string[] = [];
    const queue = [...(children.get(me.id) ?? [])];
    while (queue.length) {
      const id = queue.shift()!;
      if (managerOf.includes(id)) continue;
      managerOf.push(id);
      queue.push(...(children.get(id) ?? []));
    }

    const permissions = await this.permissionsOf(me.id, me.role);
    return {
      id: me.id, role: me.role, locationId: me.locationId, departmentId: me.departmentId, managerOf, projects: me.memberships, permissions,
      mustChangePassword: me.mustChangePassword,
    };
  }

  ability(actor: Actor) {
    return defineAbilityFor(actor);
  }
}

/** Revocation time, rounded down to whole seconds because token `iat` is in seconds. */
export function sessionCutoff(now = Date.now()) {
  return new Date(Math.floor(now / 1000) * 1000);
}

/** False when the token was issued before the person's sessions were revoked (or has no issue time). */
export function tokenStillValid(issuedAt: number | undefined, validFrom: Date | null) {
  if (!validFrom) return true;
  return typeof issuedAt === 'number' && issuedAt * 1000 >= validFrom.getTime();
}

/** Throws 403 unless the actor may perform `action` on this record. */
export function assertCan(ability: AppAbility, action: Action, type: SubjectName, record: Record<string, unknown> = {}) {
  if (!ability.can(action, asSubject(type, { ...record }) as never)) {
    throw new ForbiddenException(`Not allowed to ${action} ${type}`);
  }
}

export function canDo(ability: AppAbility, action: Action, type: SubjectName, record: Record<string, unknown> = {}) {
  return ability.can(action, asSubject(type, { ...record }) as never);
}

@Global()
@Module({
  providers: [AccessService],
  exports: [AccessService],
})
export class AccessModule {}
