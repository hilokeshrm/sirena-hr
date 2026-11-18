import { Controller, Get, Injectable, Module, Query } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { CurrentAbility } from '../auth/auth.guard';
import { toDbDate } from '../common/dates';
import { PrismaService } from '../prisma/prisma.service';
import { AppAbility, assertCan } from '../access/access.service';

/** Plain English for each action the rest of the app records. */
const ACTIONS: Record<string, string> = {
  login: 'Signed in',
  'login-locked': 'Locked out after wrong passwords',
  'change-password': 'Changed their password',
  'change-password-locked': 'Locked out changing password',
  'password-reset': 'Password reset',
  'force-password-change': 'Staff asked to pick new passwords',
  invite: 'Sent a sign-up invite',
  'accept-invite': 'Accepted an invite',
  create: 'Added',
  update: 'Edited',
  delete: 'Deleted',
  'change-role': 'Changed a role',
  'role-change': 'Changed a role',
  'set-permission': 'Changed access',
  'reset-permissions': 'Reset access to defaults',
  'people-setup': 'Bulk setup of roles and passwords',
  apply: 'Applied for leave',
  approve: 'Approved leave',
  reject: 'Declined leave',
  cancel: 'Cancelled leave',
  adjust: 'Adjusted a leave balance',
  accrue: 'Ran the monthly leave credit',
  'open-year': 'Opened a leave year',
  'check-in': 'Checked in',
  'check-out': 'Checked out',
  'book-meal': 'Booked lunch',
  'set-menu': 'Set the lunch menu',
  publish: 'Published a policy',
  'new-version': 'Wrote a new policy version',
  remind: 'Sent a policy reminder',
  ack: 'Acknowledged a policy',
  upload: 'Uploaded a file',
  download: 'Downloaded a file',
  'set-member': 'Changed project members',
  reset: 'Reset',
};

const describe = (action: string) => ACTIONS[action] ?? action.replace(/-/g, ' ');

type Row = Prisma.AuditLogGetPayload<object>;

@Injectable()
export class AuditLogService {
  constructor(private prisma: PrismaService) {}

  /** One page of the log, newest first, with the person's name filled in. */
  async list(ability: AppAbility, q: { who?: string; action?: string; entity?: string; from?: string; to?: string; take?: number; cursor?: string }) {
    assertCan(ability, 'read', 'AuditLog');
    const take = Math.min(Math.max(Number(q.take) || 50, 1), 200);

    const where: Prisma.AuditLogWhereInput = {};
    if (q.action) where.action = q.action;
    if (q.entity) where.entity = q.entity;
    if (q.from || q.to) {
      where.at = {
        ...(q.from ? { gte: toDbDate(q.from.slice(0, 10)) } : {}),
        // "to" is a day, so include everything up to the end of it.
        ...(q.to ? { lt: new Date(toDbDate(q.to.slice(0, 10)).getTime() + 86_400_000) } : {}),
      };
    }
    if (q.who) {
      const people = await this.prisma.employee.findMany({
        where: { OR: [{ fullName: { contains: q.who, mode: 'insensitive' } }, { email: { contains: q.who, mode: 'insensitive' } }, { code: { contains: q.who, mode: 'insensitive' } }] },
        select: { id: true },
        take: 200,
      });
      where.actorId = { in: people.map((p) => p.id) };
    }

    const rows = await this.prisma.auditLog.findMany({
      where,
      orderBy: { at: 'desc' },
      take: take + 1,
      ...(q.cursor ? { cursor: { id: q.cursor }, skip: 1 } : {}),
    });
    const page = rows.slice(0, take);
    return { items: await this.withPeople(page), nextCursor: rows.length > take ? page[page.length - 1].id : null };
  }

  /** Who did what, over the last day and week, so one screen shows whether anything looks odd. */
  async summary(ability: AppAbility) {
    assertCan(ability, 'read', 'AuditLog');
    const now = Date.now();
    const day = new Date(now - 86_400_000);
    const week = new Date(now - 7 * 86_400_000);
    const [today, lastWeek, byAction, signIns, lockouts, people] = await Promise.all([
      this.prisma.auditLog.count({ where: { at: { gte: day } } }),
      this.prisma.auditLog.count({ where: { at: { gte: week } } }),
      this.prisma.auditLog.groupBy({ by: ['action'], where: { at: { gte: week } }, _count: true, orderBy: { _count: { action: 'desc' } }, take: 8 }),
      this.prisma.auditLog.findMany({ where: { at: { gte: day }, action: 'login' }, select: { actorId: true }, distinct: ['actorId'] }),
      this.prisma.auditLog.count({ where: { at: { gte: week }, action: { in: ['login-locked', 'change-password-locked'] } } }),
      this.prisma.employee.count({ where: { status: { in: ['ACTIVE', 'ON_NOTICE'] } } }),
    ]);
    return {
      entriesToday: today,
      entriesThisWeek: lastWeek,
      signedInToday: signIns.length,
      peopleActive: people,
      lockoutsThisWeek: lockouts,
      topActions: byAction.map((a) => ({ action: a.action, label: describe(a.action), count: a._count })),
    };
  }

  /** The action and entity names present in the log, so the filters only offer what exists. */
  async filters(ability: AppAbility) {
    assertCan(ability, 'read', 'AuditLog');
    const [actions, entities] = await Promise.all([
      this.prisma.auditLog.groupBy({ by: ['action'], orderBy: { action: 'asc' } }),
      this.prisma.auditLog.groupBy({ by: ['entity'], orderBy: { entity: 'asc' } }),
    ]);
    return {
      actions: actions.map((a) => ({ value: a.action, label: describe(a.action) })),
      entities: entities.map((e) => e.entity),
    };
  }

  private async withPeople(rows: Row[]) {
    const ids = [...new Set(rows.map((r) => r.actorId).filter((id): id is string => !!id))];
    const people = ids.length
      ? await this.prisma.employee.findMany({ where: { id: { in: ids } }, select: { id: true, fullName: true, email: true, code: true } })
      : [];
    const by = Object.fromEntries(people.map((p) => [p.id, p]));
    return rows.map((r) => ({
      id: r.id,
      at: r.at,
      action: r.action,
      label: describe(r.action),
      entity: r.entity,
      entityId: r.entityId,
      meta: r.meta,
      // Entries made by a script or the system itself have no person attached.
      actor: r.actorId ? (by[r.actorId] ?? { id: r.actorId, fullName: 'Removed employee', email: null, code: null }) : null,
    }));
  }
}

@Controller('audit')
export class AuditController {
  constructor(private svc: AuditLogService) {}

  @Get()
  list(
    @CurrentAbility() ability: AppAbility,
    @Query('who') who?: string,
    @Query('action') action?: string,
    @Query('entity') entity?: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('take') take?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.svc.list(ability, { who, action, entity, from, to, take: take ? Number(take) : undefined, cursor });
  }

  @Get('summary')
  summary(@CurrentAbility() ability: AppAbility) {
    return this.svc.summary(ability);
  }

  @Get('filters')
  filters(@CurrentAbility() ability: AppAbility) {
    return this.svc.filters(ability);
  }
}

@Module({
  controllers: [AuditController],
  providers: [AuditLogService],
})
export class AuditModule {}
