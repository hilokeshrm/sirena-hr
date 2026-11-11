import { BadRequestException, Body, Controller, Get, HttpCode, Injectable, Module, Param, Post, Put, Query, Req } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DayMode, MealChoice } from '@prisma/client';
import { IsBoolean, IsEnum, IsLatitude, IsLongitude, IsNumber, IsOptional, IsString, Min } from 'class-validator';
import type { Request } from 'express';
import { Actor, AppAbility, assertCan, canDo } from '../access/access.service';
import { AuditService } from '../common/audit.service';
import { addDays, eachDay, fromDbDate, hhmmToMinutes, isWeekend, minutesNowIST, toDbDate, todayIST } from '../common/dates';
import { PrismaService } from '../prisma/prisma.service';
import { CurrentAbility, CurrentActor } from '../auth/auth.guard';

class CheckInDto {
  @IsEnum(DayMode) mode!: DayMode;
  /** true when the app checked in by itself after joining office Wi-Fi */
  @IsOptional() @IsBoolean() auto?: boolean;
  @IsOptional() @IsString() ssid?: string;
  @IsOptional() @IsString() bssid?: string;
  /** Device position, when the person allowed location access */
  @IsOptional() @IsLatitude() latitude?: number;
  @IsOptional() @IsLongitude() longitude?: number;
  @IsOptional() @IsNumber() @Min(0) accuracyM?: number;
}

class CheckOutDto {
  @IsOptional() @IsBoolean() auto?: boolean;
}

class PlanDto {
  @IsEnum(DayMode) mode!: DayMode;
}

class MealDto {
  @IsEnum(MealChoice) choice!: MealChoice;
}

class MenuDto {
  @IsString() locationId!: string;
  @IsString() vegMenu!: string;
  @IsString() nonVegMenu!: string;
}

function clientIp(req: Request): string {
  return (req.ip ?? '').replace(/^::ffff:/, '');
}

/** Metres between two points (haversine). */
function distanceM(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const rad = Math.PI / 180;
  const a = Math.sin(((lat2 - lat1) * rad) / 2) ** 2 + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(((lon2 - lon1) * rad) / 2) ** 2;
  return 2 * 6_371_000 * Math.asin(Math.sqrt(a));
}

// A fix less precise than this can't place someone inside an office reliably.
const MAX_GPS_ACCURACY_M = 200;

@Injectable()
export class AttendanceService {
  constructor(private prisma: PrismaService, private audit: AuditService, private cfg: ConfigService) {}

  private async myContext(employeeId: string) {
    const me = await this.prisma.employee.findUniqueOrThrow({ where: { id: employeeId }, select: { id: true, locationId: true, workMode: true } });
    // People without a location (hybrid/remote in the HR sheet) can check in at any office.
    const networks = await this.prisma.officeNetwork.findMany({ where: me.locationId ? { locationId: me.locationId } : {} });
    return { me, networks };
  }

  private async onLeave(employeeId: string, day: string) {
    const d = toDbDate(day);
    return !!(await this.prisma.leaveRequest.findFirst({ where: { employeeId, status: 'APPROVED', fromDate: { lte: d }, toDate: { gte: d } } }));
  }

  /** What the app needs to run check-in: today's record and the office Wi-Fi to look for. */
  async today(actor: Actor) {
    const { networks } = await this.myContext(actor.id);
    const rec = await this.prisma.attendance.findUnique({ where: { employeeId_date: { employeeId: actor.id, date: toDbDate(todayIST()) } } });
    return {
      date: todayIST(),
      record: rec,
      officeNetworks: networks.map((n) => ({ ssid: n.ssid, bssids: n.bssids, latitude: n.latitude, longitude: n.longitude, radiusM: n.radiusM })),
      onLeave: await this.onLeave(actor.id, todayIST()),
    };
  }

  async checkIn(actor: Actor, dto: CheckInDto, req: Request) {
    const day = todayIST();
    if (await this.onLeave(actor.id, day)) throw new BadRequestException("You're on approved leave today");
    const { networks } = await this.myContext(actor.id);
    const ip = clientIp(req);
    const bssid = dto.bssid?.toLowerCase();
    const byBssid = !!bssid && networks.some((n) => n.bssids.map((b) => b.toLowerCase()).includes(bssid));
    const byIp = networks.some((n) => n.publicIp && n.publicIp === ip);
    const { latitude: lat, longitude: lon, accuracyM } = dto;
    const hasFix = lat != null && lon != null && (accuracyM ?? 0) <= MAX_GPS_ACCURACY_M;
    const byGps = hasFix && networks.some((n) => n.latitude != null && n.longitude != null && distanceM(lat, lon, n.latitude, n.longitude) <= n.radiusM);
    const atOffice = byBssid || byIp || byGps;
    if (dto.auto && !atOffice) throw new BadRequestException('Automatic check-in only works on office Wi-Fi or at the office');

    const data = {
      mode: dto.mode,
      method: dto.auto && (byBssid || byIp) ? ('WIFI' as const) : byGps ? ('GPS' as const) : ('MANUAL' as const),
      flagged: dto.mode === 'OFFICE' && !atOffice,
      ip, ssid: dto.ssid, bssid,
      latitude: lat ?? null, longitude: lon ?? null, accuracyM: accuracyM ?? null,
    };
    const existing = await this.prisma.attendance.findUnique({ where: { employeeId_date: { employeeId: actor.id, date: toDbDate(day) } } });
    const rec = existing
      ? await this.prisma.attendance.update({ where: { id: existing.id }, data: { ...data, checkOutAt: null } })
      : await this.prisma.attendance.create({ data: { ...data, employeeId: actor.id, date: toDbDate(day), checkInAt: new Date() } });
    if (dto.mode === 'WFH') await this.setPlan(actor, day, 'WFH');
    await this.audit.log(actor.id, 'check-in', 'Attendance', rec.id, { method: rec.method, flagged: rec.flagged });
    return rec;
  }

  async checkOut(actor: Actor) {
    const rec = await this.prisma.attendance.findUnique({ where: { employeeId_date: { employeeId: actor.id, date: toDbDate(todayIST()) } } });
    if (!rec) throw new BadRequestException("You haven't checked in today");
    return this.prisma.attendance.update({ where: { id: rec.id }, data: { checkOutAt: new Date() } });
  }

  async history(actor: Actor, from: string, to: string) {
    const rows = await this.prisma.attendance.findMany({
      where: { employeeId: actor.id, date: { gte: toDbDate(from), lte: toDbDate(to) } },
      orderBy: { date: 'asc' },
    });
    return rows.map((r) => ({ ...r, date: fromDbDate(r.date) }));
  }

  /** Everyone's check-ins for a day, limited to who this person may see. */
  async day(actor: Actor, ability: AppAbility, day: string) {
    const rows = await this.prisma.attendance.findMany({
      where: { date: toDbDate(day) },
      include: { employee: { select: { id: true, fullName: true, code: true, locationId: true } } },
      orderBy: { checkInAt: 'asc' },
    });
    const visible = rows.filter((r) => canDo(ability, 'read', 'Attendance', { employeeId: r.employeeId, employeeLocationId: r.employee.locationId }));
    return {
      date: day,
      summary: {
        checkedIn: visible.length,
        office: visible.filter((r) => r.mode === 'OFFICE').length,
        wfh: visible.filter((r) => r.mode === 'WFH').length,
        flagged: visible.filter((r) => r.flagged).length,
      },
      rows: visible.map((r) => ({ ...r, date: fromDbDate(r.date) })),
    };
  }

  // ── Work plans & lunch ──

  async setPlan(actor: Actor, day: string, mode: DayMode) {
    if (day < todayIST()) throw new BadRequestException('Past days cannot be changed');
    await this.prisma.workPlan.upsert({
      where: { employeeId_date: { employeeId: actor.id, date: toDbDate(day) } },
      create: { employeeId: actor.id, date: toDbDate(day), mode },
      update: { mode },
    });
    if (mode === 'WFH') {
      await this.prisma.mealBooking.updateMany({ where: { employeeId: actor.id, date: toDbDate(day), status: 'BOOKED' }, data: { status: 'CANCELLED' } });
    }
    return { date: day, mode };
  }

  private cutoffPassed(day: string) {
    const today = todayIST();
    if (day < today) return true;
    return day === today && minutesNowIST() >= hhmmToMinutes(this.cfg.get('MEAL_CUTOFF', '10:30'));
  }

  /** Each working day with its plan, lunch booking, menu and whether it can still be changed. */
  async week(actor: Actor, from: string, to: string) {
    const { me } = await this.myContext(actor.id);
    const days = eachDay(from, to).filter((d) => !isWeekend(d));
    const range = { gte: toDbDate(from), lte: toDbDate(to) };
    const [plans, bookings, menus, holidays, leaves, att] = await Promise.all([
      this.prisma.workPlan.findMany({ where: { employeeId: actor.id, date: range } }),
      this.prisma.mealBooking.findMany({ where: { employeeId: actor.id, date: range } }),
      this.prisma.mealMenu.findMany({ where: { locationId: me.locationId ?? '_none_', date: range } }),
      this.prisma.holiday.findMany({ where: { optional: false, date: range, OR: [{ locationId: null }, { locationId: me.locationId }] } }),
      this.prisma.leaveRequest.findMany({ where: { employeeId: actor.id, status: 'APPROVED', fromDate: { lte: range.lte }, toDate: { gte: range.gte } } }),
      this.prisma.attendance.findMany({ where: { employeeId: actor.id, date: range } }),
    ]);
    const key = (d: Date) => fromDbDate(d);
    return days.map((day) => {
      const holiday = holidays.find((h) => key(h.date) === day);
      const onLeave = leaves.some((l) => key(l.fromDate) <= day && key(l.toDate) >= day);
      const plan = plans.find((p) => key(p.date) === day)?.mode;
      const checkedIn = att.find((a) => key(a.date) === day)?.mode;
      const mode: DayMode = checkedIn ?? plan ?? (me.workMode === 'REMOTE' ? 'WFH' : 'OFFICE');
      const booking = bookings.find((b) => key(b.date) === day && b.status !== 'CANCELLED');
      const menu = menus.find((m) => key(m.date) === day);
      let reason: string | null = null;
      if (holiday) reason = `Holiday: ${holiday.name}`;
      else if (onLeave) reason = "You're on leave";
      else if (mode === 'WFH') reason = 'Working from home';
      else if (this.cutoffPassed(day)) reason = 'Booking closed';
      return {
        date: day, mode, onLeave, holiday: holiday?.name ?? null,
        booking: booking ? { choice: booking.choice, status: booking.status, passCode: booking.passCode } : null,
        menu: menu ? { veg: menu.vegMenu, nonVeg: menu.nonVegMenu } : null,
        canBook: reason === null, reason,
      };
    });
  }

  async book(actor: Actor, day: string, choice: MealChoice) {
    const [info] = await this.week(actor, day, day);
    if (!info) throw new BadRequestException('Lunch is not served on weekends');
    if (!info.canBook) throw new BadRequestException(info.reason ?? 'Booking not allowed');
    const passCode = `${String.fromCharCode(65 + Math.floor(Math.random() * 6))}-${100 + Math.floor(Math.random() * 900)}`;
    const b = await this.prisma.mealBooking.upsert({
      where: { employeeId_date: { employeeId: actor.id, date: toDbDate(day) } },
      create: { employeeId: actor.id, date: toDbDate(day), choice, passCode, status: 'BOOKED' },
      update: { choice, status: 'BOOKED' },
    });
    await this.audit.log(actor.id, 'book-meal', 'MealBooking', b.id, { day, choice });
    return { ...b, date: fromDbDate(b.date) };
  }

  /** Kitchen counts for a day at one location. */
  async counts(ability: AppAbility, day: string, locationId?: string) {
    assertCan(ability, 'read', 'MealReport');
    const where = { date: toDbDate(day), status: { not: 'CANCELLED' as const }, ...(locationId ? { employee: { locationId } } : {}) };
    const rows = await this.prisma.mealBooking.groupBy({ by: ['choice'], where, _count: true });
    const n = (c: MealChoice) => rows.find((r) => r.choice === c)?._count ?? 0;
    return { date: day, veg: n('VEG'), nonVeg: n('NON_VEG'), none: n('NONE'), total: n('VEG') + n('NON_VEG') };
  }

  /** Who booked lunch for a day at one location, for the kitchen and admins. */
  async bookings(ability: AppAbility, day: string, locationId?: string) {
    assertCan(ability, 'read', 'MealReport');
    const rows = await this.prisma.mealBooking.findMany({
      where: { date: toDbDate(day), status: { not: 'CANCELLED' }, choice: { not: 'NONE' }, ...(locationId ? { employee: { locationId } } : {}) },
      select: { choice: true, status: true, employee: { select: { fullName: true, code: true, department: { select: { name: true } } } } },
      orderBy: { employee: { fullName: 'asc' } },
    });
    return rows.map((r) => ({ name: r.employee.fullName, code: r.employee.code, department: r.employee.department?.name ?? null, choice: r.choice, status: r.status }));
  }

  async setMenu(actor: Actor, ability: AppAbility, day: string, dto: MenuDto) {
    assertCan(ability, 'read', 'MealReport');
    await this.audit.log(actor.id, 'set-menu', 'MealMenu', `${day}:${dto.locationId}`);
    return this.prisma.mealMenu.upsert({
      where: { date_locationId: { date: toDbDate(day), locationId: dto.locationId } },
      create: { date: toDbDate(day), ...dto },
      update: { vegMenu: dto.vegMenu, nonVegMenu: dto.nonVegMenu },
    });
  }
}

const DAY = /^\d{4}-\d{2}-\d{2}$/;
function day(v: string | undefined, fallback: string) {
  const d = v ?? fallback;
  if (!DAY.test(d)) throw new BadRequestException('Dates must be YYYY-MM-DD');
  return d;
}

@Controller()
export class AttendanceController {
  constructor(private svc: AttendanceService) {}

  @Get('attendance/today')
  today(@CurrentActor() actor: Actor) {
    return this.svc.today(actor);
  }

  @Post('attendance/check-in') @HttpCode(200)
  checkIn(@CurrentActor() actor: Actor, @Body() dto: CheckInDto, @Req() req: Request) {
    return this.svc.checkIn(actor, dto, req);
  }

  @Post('attendance/check-out') @HttpCode(200)
  checkOut(@CurrentActor() actor: Actor, @Body() _dto: CheckOutDto) {
    return this.svc.checkOut(actor);
  }

  @Get('attendance/me')
  history(@CurrentActor() actor: Actor, @Query('from') from?: string, @Query('to') to?: string) {
    const t = todayIST();
    return this.svc.history(actor, day(from, addDays(t, -30)), day(to, t));
  }

  @Get('attendance/day')
  dayView(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Query('date') date?: string) {
    return this.svc.day(actor, ability, day(date, todayIST()));
  }

  @Put('plans/:date')
  plan(@CurrentActor() actor: Actor, @Param('date') date: string, @Body() dto: PlanDto) {
    return this.svc.setPlan(actor, day(date, ''), dto.mode);
  }

  @Get('meals')
  meals(@CurrentActor() actor: Actor, @Query('from') from?: string, @Query('to') to?: string) {
    const t = todayIST();
    return this.svc.week(actor, day(from, t), day(to, addDays(t, 6)));
  }

  @Put('meals/:date')
  book(@CurrentActor() actor: Actor, @Param('date') date: string, @Body() dto: MealDto) {
    return this.svc.book(actor, day(date, ''), dto.choice);
  }

  @Get('meals/counts')
  counts(@CurrentAbility() ability: AppAbility, @Query('date') date?: string, @Query('locationId') locationId?: string) {
    return this.svc.counts(ability, day(date, todayIST()), locationId);
  }

  @Get('meals/bookings')
  bookings(@CurrentAbility() ability: AppAbility, @Query('date') date?: string, @Query('locationId') locationId?: string) {
    return this.svc.bookings(ability, day(date, todayIST()), locationId);
  }

  @Put('meals/menu/:date')
  menu(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('date') date: string, @Body() dto: MenuDto) {
    return this.svc.setMenu(actor, ability, day(date, ''), dto);
  }
}

@Module({
  controllers: [AttendanceController],
  providers: [AttendanceService],
})
export class AttendanceModule {}
