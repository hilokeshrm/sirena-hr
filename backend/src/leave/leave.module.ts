import { BadRequestException, Body, Controller, Delete, Get, HttpCode, Injectable, Module, NotFoundException, Param, Patch, Post, Query } from '@nestjs/common';
import { Accrual, HalfDay, HrApproval, LeaveStatus, LeaveType, Prisma } from '@prisma/client';
import { Type } from 'class-transformer';
import { IsBoolean, IsDateString, IsEnum, IsInt, IsNumber, IsOptional, IsString, Max, Min } from 'class-validator';
import { Actor, AppAbility, assertCan, canDo } from '../access/access.service';
import { AuditService, NotifyService } from '../common/audit.service';
import { addDays, eachDay, fromDbDate, isWeekend, monthBounds, toDbDate, todayIST } from '../common/dates';
import { PrismaService } from '../prisma/prisma.service';
import { CurrentAbility, CurrentActor } from '../auth/auth.guard';

class ApplyDto {
  @IsString() leaveTypeId!: string;
  @IsDateString() fromDate!: string;
  @IsDateString() toDate!: string;
  @IsOptional() @IsEnum(HalfDay) halfDay?: HalfDay;
  @IsOptional() @IsString() reason?: string;
}

class DecisionDto {
  @IsOptional() @IsString() comment?: string;
}

class LeaveTypeDto {
  @IsOptional() @IsString() code?: string;
  @IsOptional() @IsString() name?: string;
  @IsOptional() @Type(() => Number) @IsNumber() yearlyQuota?: number | null;
  @IsOptional() @IsEnum(Accrual) accrual?: Accrual;
  @IsOptional() @Type(() => Number) @IsNumber() carryForwardMax?: number;
  @IsOptional() @IsBoolean() allowHalfDay?: boolean;
  @IsOptional() @IsBoolean() allowNegative?: boolean;
  @IsOptional() @IsInt() minNoticeDays?: number;
  @IsOptional() @IsInt() maxConsecutiveDays?: number | null;
  @IsOptional() @IsBoolean() sandwich?: boolean;
  @IsOptional() @IsEnum(HrApproval) hrApproval?: HrApproval;
  @IsOptional() @IsInt() hrApprovalAboveDays?: number;
  @IsOptional() @IsString() eligibleGender?: string | null;
  @IsOptional() @IsBoolean() active?: boolean;
}

class AdjustDto {
  @IsString() employeeId!: string;
  @IsString() leaveTypeId!: string;
  @Type(() => Number) @IsNumber() delta!: number;
  @IsString() note!: string;
}

class PeriodDto {
  @IsInt() @Min(2020) @Max(2100) year!: number;
  @IsOptional() @IsInt() @Min(1) @Max(12) month?: number;
}

class HolidayDto {
  @IsDateString() date!: string;
  @IsString() name!: string;
  @IsOptional() @IsBoolean() optional?: boolean;
  @IsOptional() @IsString() locationId?: string;
}

const REQUEST_INCLUDE = {
  leaveType: { select: { id: true, code: true, name: true } },
  employee: { select: { id: true, fullName: true, designation: true, locationId: true, managerId: true, manager: { select: { fullName: true } } } },
  approvals: { include: { approver: { select: { fullName: true } } }, orderBy: { at: 'asc' } },
} satisfies Prisma.LeaveRequestInclude;

type RequestRow = Prisma.LeaveRequestGetPayload<{ include: typeof REQUEST_INCLUDE }>;

const OPEN: LeaveStatus[] = ['PENDING_MANAGER', 'PENDING_HR'];

/** Gender-specific types (maternity, paternity, period leave) apply only to matching people. */
const eligible = (t: { eligibleGender: string | null }, gender: string | null | undefined) =>
  !t.eligibleGender || t.eligibleGender.toLowerCase() === (gender ?? '').toLowerCase();

@Injectable()
export class LeaveService {
  constructor(private prisma: PrismaService, private audit: AuditService, private notify: NotifyService) {}

  /** ABAC view of a request (adds the employee's location for HR scoping). */
  private subj(r: { employeeId: string; status: LeaveStatus; employee: { locationId: string | null } }) {
    return { employeeId: r.employeeId, status: r.status, employeeLocationId: r.employee.locationId };
  }

  private shape(r: RequestRow) {
    return { ...r, fromDate: fromDbDate(r.fromDate), toDate: fromDbDate(r.toDate), days: Number(r.days) };
  }

  async holidaySet(locationId: string | null, from: string, to: string) {
    const rows = await this.prisma.holiday.findMany({
      where: { optional: false, date: { gte: toDbDate(from), lte: toDbDate(to) }, OR: [{ locationId: null }, ...(locationId ? [{ locationId }] : [])] },
      select: { date: true },
    });
    return new Set(rows.map((h) => fromDbDate(h.date)));
  }

  /** Working days in a range, honouring weekends, holidays, half days and the sandwich rule. */
  countDays(type: Pick<LeaveType, 'sandwich'>, from: string, to: string, halfDay: HalfDay, holidays: Set<string>) {
    const days = eachDay(from, to);
    const off = (d: string) => isWeekend(d) || holidays.has(d);
    const working = days.filter((d) => !off(d));
    if (!working.length) return 0;
    if (halfDay !== 'NONE') return from === to ? 0.5 : NaN;
    if (!type.sandwich) return working.length;
    // Sandwich: weekends/holidays between the first and last leave day also count.
    const first = working[0];
    const last = working[working.length - 1];
    return days.filter((d) => d >= first && d <= last).length;
  }

  async balances(employeeId: string, year = Number(todayIST().slice(0, 4))) {
    const [me, allTypes, ledger, pending] = await Promise.all([
      this.prisma.employee.findUnique({ where: { id: employeeId }, select: { gender: true } }),
      this.prisma.leaveType.findMany({ where: { active: true }, orderBy: { code: 'asc' } }),
      this.prisma.leaveLedger.groupBy({ by: ['leaveTypeId'], where: { employeeId, year }, _sum: { delta: true } }),
      this.prisma.leaveRequest.groupBy({
        by: ['leaveTypeId'],
        where: { employeeId, status: { in: OPEN }, fromDate: { gte: toDbDate(`${year}-01-01`), lte: toDbDate(`${year}-12-31`) } },
        _sum: { days: true },
      }),
    ]);
    const types = allTypes.filter((t) => eligible(t, me?.gender));
    return types.map((t) => {
      const balance = Number(ledger.find((l) => l.leaveTypeId === t.id)?._sum.delta ?? 0);
      const held = Number(pending.find((p) => p.leaveTypeId === t.id)?._sum.days ?? 0);
      return {
        leaveTypeId: t.id, code: t.code, name: t.name,
        yearlyQuota: t.yearlyQuota === null ? null : Number(t.yearlyQuota),
        balance, pending: held, available: balance - held, unlimited: t.allowNegative,
      };
    });
  }

  async preview(actor: Actor, dto: ApplyDto) {
    const type = await this.prisma.leaveType.findUnique({ where: { id: dto.leaveTypeId } });
    if (!type || !type.active) throw new BadRequestException('Unknown leave type');
    const me = await this.prisma.employee.findUniqueOrThrow({ where: { id: actor.id }, select: { locationId: true, gender: true } });
    if (!eligible(type, me.gender)) throw new BadRequestException(`${type.name} is not available to you`);
    const from = dto.fromDate.slice(0, 10);
    const to = dto.toDate.slice(0, 10);
    if (to < from) throw new BadRequestException('End date is before start date');
    const halfDay = dto.halfDay ?? 'NONE';
    if (halfDay !== 'NONE' && (!type.allowHalfDay || from !== to)) throw new BadRequestException('Half day is only for a single day');
    const holidays = await this.holidaySet(me.locationId, from, to);
    const days = this.countDays(type, from, to, halfDay, holidays);
    if (!days) throw new BadRequestException('Those dates are all weekends or holidays');
    const bal = (await this.balances(actor.id, Number(from.slice(0, 4)))).find((b) => b.leaveTypeId === type.id)!;
    return { type, from, to, halfDay, days, available: bal.available, after: bal.available - days };
  }

  async apply(actor: Actor, dto: ApplyDto) {
    const p = await this.preview(actor, dto);
    const today = todayIST();
    if (p.from < today) {
      // Back-dating is only allowed for types without notice (e.g. sick leave), up to 7 days.
      if (p.type.minNoticeDays > 0 || p.from < addDays(today, -7)) throw new BadRequestException('This leave type cannot be applied for past dates');
    } else if (p.from < addDays(today, p.type.minNoticeDays)) {
      throw new BadRequestException(`${p.type.name} needs ${p.type.minNoticeDays} days notice`);
    }
    if (p.type.maxConsecutiveDays && p.days > p.type.maxConsecutiveDays) {
      throw new BadRequestException(`${p.type.name} allows at most ${p.type.maxConsecutiveDays} days in a row`);
    }
    if (!p.type.allowNegative && p.days > p.available) {
      throw new BadRequestException(`Not enough ${p.type.name}: ${p.available} available, ${p.days} requested`);
    }
    const overlap = await this.prisma.leaveRequest.findFirst({
      where: { employeeId: actor.id, status: { in: [...OPEN, 'APPROVED'] }, fromDate: { lte: toDbDate(p.to) }, toDate: { gte: toDbDate(p.from) } },
    });
    if (overlap) throw new BadRequestException('You already have leave on some of these days');

    const me = await this.prisma.employee.findUniqueOrThrow({ where: { id: actor.id }, select: { managerId: true, fullName: true } });
    const status: LeaveStatus = me.managerId ? 'PENDING_MANAGER' : 'PENDING_HR';
    const req = await this.prisma.leaveRequest.create({
      data: { employeeId: actor.id, leaveTypeId: p.type.id, fromDate: toDbDate(p.from), toDate: toDbDate(p.to), halfDay: p.halfDay, days: p.days, reason: dto.reason, status },
      include: REQUEST_INCLUDE,
    });
    await this.audit.log(actor.id, 'apply', 'LeaveRequest', req.id);
    if (me.managerId) await this.notify.send(me.managerId, `${me.fullName} asked for ${p.days} day(s) of ${p.type.name}`, `/leave/requests/${req.id}`);
    else await this.notifyHr(actor, `${me.fullName} asked for ${p.days} day(s) of ${p.type.name}`, req.id);
    return this.shape(req);
  }

  private async notifyHr(actor: Pick<Actor, 'locationId'>, title: string, requestId: string) {
    const hr = await this.prisma.employee.findMany({
      where: { status: 'ACTIVE', OR: [{ role: 'HR_ADMIN' }, { role: 'HR', locationId: actor.locationId }] },
      select: { id: true },
    });
    await this.notify.send(hr.map((h) => h.id), title, `/leave/requests/${requestId}`);
  }

  async list(actor: Actor, ability: AppAbility, scope: 'mine' | 'approvals' | 'all', status?: LeaveStatus) {
    const where: Prisma.LeaveRequestWhereInput = status ? { status } : {};
    let rows: RequestRow[];
    if (scope === 'mine') {
      rows = await this.prisma.leaveRequest.findMany({ where: { ...where, employeeId: actor.id }, include: REQUEST_INCLUDE, orderBy: { fromDate: 'desc' } });
    } else {
      const candidates = await this.prisma.leaveRequest.findMany({
        where: scope === 'approvals' ? { status: { in: OPEN }, employeeId: { not: actor.id } } : where,
        include: REQUEST_INCLUDE, orderBy: { createdAt: 'desc' }, take: 500,
      });
      const action = scope === 'approvals' ? 'approve' : 'read';
      rows = candidates.filter((r) => canDo(ability, action, 'LeaveRequest', this.subj(r)));
    }
    return rows.map((r) => this.shape(r));
  }

  async get(ability: AppAbility, id: string) {
    const r = await this.prisma.leaveRequest.findUnique({ where: { id }, include: REQUEST_INCLUDE });
    if (!r) throw new NotFoundException();
    assertCan(ability, 'read', 'LeaveRequest', this.subj(r));
    return { ...this.shape(r), canApprove: canDo(ability, 'approve', 'LeaveRequest', this.subj(r)) };
  }

  async decide(actor: Actor, ability: AppAbility, id: string, approve: boolean, comment?: string) {
    const r = await this.prisma.leaveRequest.findUnique({ where: { id }, include: { ...REQUEST_INCLUDE, leaveType: true } });
    if (!r) throw new NotFoundException();
    assertCan(ability, 'approve', 'LeaveRequest', this.subj(r));
    const step = r.status === 'PENDING_MANAGER' ? 'MANAGER' : 'HR';
    let next: LeaveStatus;
    if (!approve) next = 'REJECTED';
    else if (step === 'MANAGER') {
      const t = r.leaveType;
      const needsHr = t.hrApproval === 'ALWAYS' || (t.hrApproval === 'ABOVE_DAYS' && Number(r.days) > t.hrApprovalAboveDays);
      next = needsHr ? 'PENDING_HR' : 'APPROVED';
    } else next = 'APPROVED';

    await this.prisma.$transaction(async (tx) => {
      // Guard against two people deciding at once.
      const res = await tx.leaveRequest.updateMany({ where: { id, status: r.status }, data: { status: next } });
      if (res.count !== 1) throw new BadRequestException('This request was already decided');
      await tx.leaveApproval.create({ data: { requestId: id, step, approverId: actor.id, approved: approve, comment } });
      if (next === 'APPROVED') {
        await tx.leaveLedger.create({
          data: { employeeId: r.employeeId, leaveTypeId: r.leaveTypeId, year: r.fromDate.getUTCFullYear(), delta: -Number(r.days), reason: 'TAKEN', refId: id },
        });
        // Approved leave cancels lunch bookings on those days.
        await tx.mealBooking.updateMany({
          where: { employeeId: r.employeeId, date: { gte: r.fromDate, lte: r.toDate }, status: 'BOOKED' },
          data: { status: 'CANCELLED' },
        });
      }
    });
    await this.audit.log(actor.id, approve ? 'approve' : 'reject', 'LeaveRequest', id, { step, comment });
    const label = `${r.leaveType.name} ${fromDbDate(r.fromDate)}${r.fromDate.getTime() === r.toDate.getTime() ? '' : ' to ' + fromDbDate(r.toDate)}`;
    if (next === 'PENDING_HR') await this.notifyHr({ locationId: r.employee.locationId }, `${r.employee.fullName}'s ${label} needs HR sign-off`, id);
    else await this.notify.send(r.employeeId, `Your ${label} was ${next === 'APPROVED' ? 'approved' : 'declined'}`, `/leave/requests/${id}`);
    return this.get(ability, id);
  }

  async cancel(actor: Actor, ability: AppAbility, id: string) {
    const r = await this.prisma.leaveRequest.findUnique({ where: { id }, include: REQUEST_INCLUDE });
    if (!r) throw new NotFoundException();
    assertCan(ability, 'cancel', 'LeaveRequest', this.subj(r));
    if (r.status === 'APPROVED' && fromDbDate(r.fromDate) <= todayIST()) throw new BadRequestException('Leave that has started cannot be cancelled. Ask HR.');
    if (!['PENDING_MANAGER', 'PENDING_HR', 'APPROVED'].includes(r.status)) throw new BadRequestException('This request cannot be cancelled');
    await this.prisma.$transaction(async (tx) => {
      await tx.leaveRequest.update({ where: { id }, data: { status: 'CANCELLED' } });
      if (r.status === 'APPROVED') {
        await tx.leaveLedger.create({
          data: { employeeId: r.employeeId, leaveTypeId: r.leaveTypeId, year: r.fromDate.getUTCFullYear(), delta: Number(r.days), reason: 'REVERSAL', refId: id },
        });
      }
    });
    await this.audit.log(actor.id, 'cancel', 'LeaveRequest', id);
    return this.get(ability, id);
  }

  /** Who is off on each day of a month: my team (same manager), my reports, or everyone for HR. */
  async calendar(actor: Actor, ability: AppAbility, month: string) {
    const { first: from, last: end } = monthBounds(month);
    const me = await this.prisma.employee.findUniqueOrThrow({ where: { id: actor.id }, select: { managerId: true, locationId: true } });
    const isHr = canDo(ability, 'read', 'LeaveRequest', { employeeId: '_', status: 'APPROVED', employeeLocationId: me.locationId });
    const team = isHr ? undefined : [actor.id, ...actor.managerOf, ...(await this.prisma.employee.findMany({ where: { managerId: me.managerId ?? '_none_' }, select: { id: true } })).map((e) => e.id)];
    const [leaves, holidays] = await Promise.all([
      this.prisma.leaveRequest.findMany({
        where: { status: { in: ['APPROVED', ...OPEN] }, fromDate: { lte: toDbDate(end) }, toDate: { gte: toDbDate(from) }, ...(team ? { employeeId: { in: team } } : {}) },
        include: { employee: { select: { id: true, fullName: true } }, leaveType: { select: { name: true } } },
      }),
      this.prisma.holiday.findMany({ where: { date: { gte: toDbDate(from), lte: toDbDate(end) }, OR: [{ locationId: null }, { locationId: me.locationId }] } }),
    ]);
    return {
      month,
      holidays: holidays.map((h) => ({ date: fromDbDate(h.date), name: h.name, optional: h.optional })),
      leaves: leaves.map((l) => ({
        id: l.id, employee: l.employee, type: l.leaveType.name, fromDate: fromDbDate(l.fromDate), toDate: fromDbDate(l.toDate),
        approved: l.status === 'APPROVED',
      })),
    };
  }

  // ── HR operations ──

  async upsertType(ability: AppAbility, id: string | null, dto: LeaveTypeDto) {
    assertCan(ability, 'manage', 'LeaveType');
    if (id) return this.prisma.leaveType.update({ where: { id }, data: dto });
    if (!dto.code || !dto.name) throw new BadRequestException('code and name are required');
    return this.prisma.leaveType.create({ data: { ...dto, code: dto.code, name: dto.name } });
  }

  async adjust(actor: Actor, ability: AppAbility, dto: AdjustDto) {
    assertCan(ability, 'manage', 'LeaveType');
    const row = await this.prisma.leaveLedger.create({
      data: { employeeId: dto.employeeId, leaveTypeId: dto.leaveTypeId, year: Number(todayIST().slice(0, 4)), delta: dto.delta, reason: 'ADJUSTMENT', note: dto.note },
    });
    await this.audit.log(actor.id, 'adjust', 'LeaveLedger', row.id, { ...dto });
    return row;
  }

  /** Monthly credit for MONTHLY types. Safe to run twice: each credit has a unique refId. */
  async accrueMonth(actor: Actor, ability: AppAbility, year: number, month: number) {
    assertCan(ability, 'manage', 'LeaveType');
    const types = await this.prisma.leaveType.findMany({ where: { active: true, accrual: 'MONTHLY', yearlyQuota: { not: null } } });
    const people = await this.prisma.employee.findMany({ where: { status: { in: ['ACTIVE', 'ON_NOTICE'] } }, select: { id: true, joinedOn: true, gender: true } });
    const monthEnd = toDbDate(monthBounds(`${year}-${String(month).padStart(2, '0')}`).nextFirst);
    let credited = 0;
    for (const t of types) {
      const perMonth = Math.round((Number(t.yearlyQuota) / 12) * 10) / 10;
      for (const p of people) {
        if (p.joinedOn && p.joinedOn >= monthEnd) continue; // not yet joined that month
        if (!eligible(t, p.gender)) continue;
        const refId = `accrual:${year}-${month}:${t.id}`;
        const exists = await this.prisma.leaveLedger.findFirst({ where: { employeeId: p.id, refId } });
        if (exists) continue;
        await this.prisma.leaveLedger.create({ data: { employeeId: p.id, leaveTypeId: t.id, year, delta: perMonth, reason: 'ACCRUAL', refId } });
        credited++;
      }
    }
    await this.audit.log(actor.id, 'accrue', 'LeaveLedger', undefined, { year, month, credited });
    return { credited };
  }

  /** Start of a leave year: up-front credits, plus carry-forward of last year's balance up to each type's cap. */
  async openYear(actor: Actor, ability: AppAbility, year: number) {
    assertCan(ability, 'manage', 'LeaveType');
    const types = await this.prisma.leaveType.findMany({ where: { active: true } });
    const people = await this.prisma.employee.findMany({ where: { status: { in: ['ACTIVE', 'ON_NOTICE', 'ONBOARDING'] } }, select: { id: true, gender: true } });
    let rows = 0;
    for (const p of people) {
      const prev = await this.balances(p.id, year - 1);
      for (const t of types) {
        if (!eligible(t, p.gender)) continue;
        const ref = `open:${year}:${t.id}`;
        if (await this.prisma.leaveLedger.findFirst({ where: { employeeId: p.id, refId: ref } })) continue;
        const carry = Math.max(0, Math.min(prev.find((b) => b.leaveTypeId === t.id)?.balance ?? 0, Number(t.carryForwardMax)));
        if (carry > 0) {
          await this.prisma.leaveLedger.create({ data: { employeeId: p.id, leaveTypeId: t.id, year, delta: carry, reason: 'CARRY_FORWARD', refId: ref } });
          rows++;
        }
        if (t.accrual === 'UPFRONT' && t.yearlyQuota !== null) {
          await this.prisma.leaveLedger.create({ data: { employeeId: p.id, leaveTypeId: t.id, year, delta: Number(t.yearlyQuota), reason: 'OPENING', refId: `${ref}:upfront` } });
          rows++;
        }
      }
    }
    await this.audit.log(actor.id, 'open-year', 'LeaveLedger', undefined, { year, rows });
    return { rows };
  }

  holidays(year: number, locationId?: string) {
    return this.prisma.holiday
      .findMany({
        where: { date: { gte: toDbDate(`${year}-01-01`), lte: toDbDate(`${year}-12-31`) }, ...(locationId ? { OR: [{ locationId: null }, { locationId }] } : {}) },
        include: { location: { select: { name: true } } },
        orderBy: { date: 'asc' },
      })
      .then((rows) => rows.map((h) => ({ ...h, date: fromDbDate(h.date) })));
  }

  async addHoliday(actor: Actor, ability: AppAbility, dto: HolidayDto) {
    assertCan(ability, 'manage', 'Holiday');
    const h = await this.prisma.holiday.create({ data: { date: toDbDate(dto.date.slice(0, 10)), name: dto.name, optional: dto.optional ?? false, locationId: dto.locationId ?? null } });
    await this.audit.log(actor.id, 'create', 'Holiday', h.id);
    return h;
  }

  async deleteHoliday(actor: Actor, ability: AppAbility, id: string) {
    assertCan(ability, 'manage', 'Holiday');
    await this.prisma.holiday.delete({ where: { id } });
    await this.audit.log(actor.id, 'delete', 'Holiday', id);
    return { ok: true };
  }
}

@Controller()
export class LeaveController {
  constructor(private svc: LeaveService, private prisma: PrismaService) {}

  @Get('leave/types')
  types() {
    return this.prisma.leaveType.findMany({ orderBy: { code: 'asc' } });
  }

  @Post('leave/types')
  createType(@CurrentAbility() ability: AppAbility, @Body() dto: LeaveTypeDto) {
    return this.svc.upsertType(ability, null, dto);
  }

  @Patch('leave/types/:id')
  updateType(@CurrentAbility() ability: AppAbility, @Param('id') id: string, @Body() dto: LeaveTypeDto) {
    return this.svc.upsertType(ability, id, dto);
  }

  @Get('leave/balances')
  async balances(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Query('employeeId') employeeId?: string, @Query('year') year?: string) {
    const id = employeeId ?? actor.id;
    if (id !== actor.id) {
      const emp = await this.prisma.employee.findUnique({ where: { id }, select: { locationId: true } });
      if (!emp) throw new NotFoundException();
      assertCan(ability, 'read', 'LeaveRequest', { employeeId: id, status: 'APPROVED', employeeLocationId: emp.locationId });
    }
    return this.svc.balances(id, year ? Number(year) : undefined);
  }

  @Post('leave/preview') @HttpCode(200)
  async preview(@CurrentActor() actor: Actor, @Body() dto: ApplyDto) {
    const p = await this.svc.preview(actor, dto);
    return { days: p.days, available: p.available, after: p.after };
  }

  @Get('leave/requests')
  list(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Query('scope') scope: 'mine' | 'approvals' | 'all' = 'mine', @Query('status') status?: LeaveStatus) {
    return this.svc.list(actor, ability, scope, status);
  }

  @Post('leave/requests')
  apply(@CurrentActor() actor: Actor, @Body() dto: ApplyDto) {
    return this.svc.apply(actor, dto);
  }

  @Get('leave/requests/:id')
  get(@CurrentAbility() ability: AppAbility, @Param('id') id: string) {
    return this.svc.get(ability, id);
  }

  @Post('leave/requests/:id/approve') @HttpCode(200)
  approve(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string, @Body() dto: DecisionDto) {
    return this.svc.decide(actor, ability, id, true, dto.comment);
  }

  @Post('leave/requests/:id/reject') @HttpCode(200)
  reject(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string, @Body() dto: DecisionDto) {
    return this.svc.decide(actor, ability, id, false, dto.comment);
  }

  @Post('leave/requests/:id/cancel') @HttpCode(200)
  cancel(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string) {
    return this.svc.cancel(actor, ability, id);
  }

  @Get('leave/calendar')
  calendar(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Query('month') month: string = todayIST().slice(0, 7)) {
    if (!/^\d{4}-\d{2}$/.test(month)) throw new BadRequestException('month must be YYYY-MM');
    return this.svc.calendar(actor, ability, month);
  }

  @Post('leave/adjust')
  adjust(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Body() dto: AdjustDto) {
    return this.svc.adjust(actor, ability, dto);
  }

  @Post('leave/accrue') @HttpCode(200)
  accrue(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Body() dto: PeriodDto) {
    if (!dto.month) throw new BadRequestException('month is required');
    return this.svc.accrueMonth(actor, ability, dto.year, dto.month);
  }

  @Post('leave/open-year') @HttpCode(200)
  openYear(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Body() dto: PeriodDto) {
    return this.svc.openYear(actor, ability, dto.year);
  }

  @Get('holidays')
  holidays(@Query('year') year?: string, @Query('locationId') locationId?: string) {
    return this.svc.holidays(year ? Number(year) : Number(todayIST().slice(0, 4)), locationId);
  }

  @Post('holidays')
  addHoliday(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Body() dto: HolidayDto) {
    return this.svc.addHoliday(actor, ability, dto);
  }

  @Delete('holidays/:id')
  deleteHoliday(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string) {
    return this.svc.deleteHoliday(actor, ability, id);
  }
}

@Module({
  controllers: [LeaveController],
  providers: [LeaveService],
  exports: [LeaveService],
})
export class LeaveModule {}
