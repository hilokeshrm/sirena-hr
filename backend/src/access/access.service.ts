import { AbilityBuilder, createMongoAbility, MongoAbility, MongoQuery, subject as asSubject } from '@casl/ability';
import { ForbiddenException, Global, Injectable, Module, UnauthorizedException } from '@nestjs/common';
import { ProjectRole, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

/** Everything the access rules know about the signed-in person. */
export interface Actor {
  id: string;
  role: Role;
  locationId: string | null;
  departmentId: string | null;
  /** Everyone below this person in the reporting tree. */
  managerOf: string[];
  projects: { projectId: string; role: ProjectRole }[];
}

export type Action =
  | 'manage' | 'read' | 'create' | 'update' | 'delete'
  | 'approve' | 'cancel' | 'readSensitive' | 'ack' | 'book' | 'upload';

export type SubjectName =
  | 'Employee' | 'LeaveRequest' | 'LeaveType' | 'Holiday' | 'Attendance' | 'MealBooking' | 'MealReport'
  | 'Project' | 'Task' | 'Folder' | 'Policy' | 'PolicyVersion' | 'Invite' | 'OfficeNetwork' | 'AuditLog' | 'all';

export type AppAbility = MongoAbility<[Action, SubjectName | Record<string, unknown>]>;

const HR_ROLES: Role[] = ['HR', 'HR_ADMIN'];

/**
 * Attribute-based access rules. Each rule reads attributes of the person
 * (role, location, reports, projects) and of the record (owner, status, project, sensitivity).
 * Anything not allowed here is denied.
 */
export function defineAbilityFor(a: Actor): AppAbility {
  const { can, cannot, build } = new AbilityBuilder<AppAbility>(createMongoAbility);
  const projectIds = a.projects.map((p) => p.projectId);
  const leadProjectIds = a.projects.filter((p) => p.role !== 'MEMBER').map((p) => p.projectId);

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

  // ── HR: scoped to their own location; HR Admin: all locations ──
  if (HR_ROLES.includes(a.role)) {
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

  // Nobody approves their own leave — this overrides every rule above.
  cannot('approve', 'LeaveRequest', { employeeId: a.id });

  return build();
}

@Injectable()
export class AccessService {
  constructor(private prisma: PrismaService) {}

  async loadActor(employeeId: string): Promise<Actor> {
    const me = await this.prisma.employee.findUnique({
      where: { id: employeeId },
      select: { id: true, role: true, status: true, locationId: true, departmentId: true, memberships: { select: { projectId: true, role: true } } },
    });
    if (!me || me.status === 'EXITED') throw new UnauthorizedException();

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

    return { id: me.id, role: me.role, locationId: me.locationId, departmentId: me.departmentId, managerOf, projects: me.memberships };
  }

  ability(actor: Actor) {
    return defineAbilityFor(actor);
  }
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
