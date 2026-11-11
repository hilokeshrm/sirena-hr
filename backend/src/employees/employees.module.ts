import { BadRequestException, Body, Controller, ForbiddenException, Get, Injectable, Module, NotFoundException, Param, Patch, Post, Query } from '@nestjs/common';
import { EmployeeStatus, EmploymentType, FoodPref, Prisma, Role, WorkMode } from '@prisma/client';
import { Type } from 'class-transformer';
import { IsDateString, IsEmail, IsEnum, IsNumber, IsOptional, IsString } from 'class-validator';
import { AccessService, Actor, AppAbility, assertCan, canDo } from '../access/access.service';
import { AuditService } from '../common/audit.service';
import { fromDbDate, sentKeys, toDbDate, todayIST } from '../common/dates';
import { PrismaService } from '../prisma/prisma.service';
import { CurrentAbility, CurrentActor } from '../auth/auth.guard';

class EmployeeDto {
  @IsOptional() @IsString() fullName?: string;
  @IsOptional() @IsString() preferredName?: string;
  @IsOptional() @IsEmail() email?: string;
  @IsOptional() @IsDateString() dateOfBirth?: string;
  @IsOptional() @IsString() gender?: string;
  @IsOptional() @IsString() bloodGroup?: string;
  @IsOptional() @IsEnum(FoodPref) foodPref?: FoodPref;
  @IsOptional() @IsEmail() personalEmail?: string;
  @IsOptional() @IsString() phone?: string;
  @IsOptional() @IsString() address?: string;
  @IsOptional() @IsString() emergencyName?: string;
  @IsOptional() @IsString() emergencyRelation?: string;
  @IsOptional() @IsString() emergencyPhone?: string;
  @IsOptional() @IsString() departmentId?: string;
  @IsOptional() @IsString() designation?: string;
  @IsOptional() @IsString() locationId?: string;
  @IsOptional() @IsString() managerId?: string;
  @IsOptional() @IsEnum(WorkMode) workMode?: WorkMode;
  @IsOptional() @IsEnum(EmploymentType) employmentType?: EmploymentType;
  @IsOptional() @IsEnum(EmployeeStatus) status?: EmployeeStatus;
  @IsOptional() @IsEnum(Role) role?: Role;
  @IsOptional() @IsDateString() joinedOn?: string;
  @IsOptional() @IsString() qualification?: string;
  @IsOptional() @Type(() => Number) @IsNumber() experienceYears?: number;
}

/** Fields anyone may update on their own record. */
const SELF_EDITABLE: (keyof EmployeeDto)[] = [
  'preferredName', 'phone', 'personalEmail', 'address', 'emergencyName', 'emergencyRelation', 'emergencyPhone', 'foodPref', 'bloodGroup',
];

const PUBLIC_SELECT = {
  id: true, code: true, email: true, fullName: true, preferredName: true, designation: true, workMode: true, status: true,
  department: { select: { id: true, name: true } },
  location: { select: { id: true, name: true } },
  manager: { select: { id: true, fullName: true } },
} satisfies Prisma.EmployeeSelect;

const RESTRICTED_SELECT = {
  ...PUBLIC_SELECT,
  role: true, dateOfBirth: true, gender: true, bloodGroup: true, foodPref: true, personalEmail: true, phone: true, address: true,
  emergencyName: true, emergencyRelation: true, emergencyPhone: true, employmentType: true, joinedOn: true,
  qualification: true, experienceYears: true, locationId: true, departmentId: true, managerId: true,
} satisfies Prisma.EmployeeSelect;

@Injectable()
export class EmployeesService {
  constructor(private prisma: PrismaService, private audit: AuditService, private access: AccessService) {}

  /** Directory with where everyone is today. */
  async list(q?: string, departmentId?: string, includeExited = false) {
    const today = toDbDate(todayIST());
    const where: Prisma.EmployeeWhereInput = {
      ...(includeExited ? {} : { status: { not: 'EXITED' } }),
      ...(departmentId ? { departmentId } : {}),
      ...(q ? { OR: [{ fullName: { contains: q, mode: 'insensitive' } }, { designation: { contains: q, mode: 'insensitive' } }, { code: { contains: q, mode: 'insensitive' } }] } : {}),
    };
    const [people, onLeave, attendance] = await Promise.all([
      this.prisma.employee.findMany({ where, select: PUBLIC_SELECT, orderBy: { fullName: 'asc' } }),
      this.prisma.leaveRequest.findMany({ where: { status: 'APPROVED', fromDate: { lte: today }, toDate: { gte: today } }, select: { employeeId: true } }),
      this.prisma.attendance.findMany({ where: { date: today }, select: { employeeId: true, mode: true } }),
    ]);
    const leaveSet = new Set(onLeave.map((l) => l.employeeId));
    const modeOf = new Map(attendance.map((a) => [a.employeeId, a.mode]));
    return people.map((p) => ({ ...p, today: leaveSet.has(p.id) ? 'ON_LEAVE' : (modeOf.get(p.id) ?? 'NOT_IN') }));
  }

  async get(ability: AppAbility, id: string) {
    const emp = await this.prisma.employee.findUnique({ where: { id }, select: RESTRICTED_SELECT });
    if (!emp) throw new NotFoundException();
    if (canDo(ability, 'readSensitive', 'Employee', { id: emp.id, locationId: emp.locationId })) {
      return { ...emp, dateOfBirth: emp.dateOfBirth ? fromDbDate(emp.dateOfBirth) : null, joinedOn: emp.joinedOn ? fromDbDate(emp.joinedOn) : null, restricted: true };
    }
    const pub: Record<string, unknown> = {};
    for (const k of Object.keys(PUBLIC_SELECT)) pub[k] = (emp as Record<string, unknown>)[k];
    return { ...pub, restricted: false };
  }

  private toData(dto: EmployeeDto) {
    const { dateOfBirth, joinedOn, experienceYears, ...rest } = dto;
    return {
      ...rest,
      ...(dto.email ? { email: dto.email.toLowerCase() } : {}),
      ...(dateOfBirth ? { dateOfBirth: toDbDate(dateOfBirth.slice(0, 10)) } : {}),
      ...(joinedOn ? { joinedOn: toDbDate(joinedOn.slice(0, 10)) } : {}),
      ...(experienceYears !== undefined ? { experienceYears } : {}),
    };
  }

  async create(actor: Actor, ability: AppAbility, dto: EmployeeDto) {
    if (!dto.fullName || !dto.email) throw new BadRequestException('fullName and email are required');
    assertCan(ability, 'create', 'Employee', { locationId: dto.locationId ?? null });
    if (dto.role && dto.role !== 'EMPLOYEE' && actor.role !== 'SUPER_ADMIN') throw new ForbiddenException('Only a super admin can assign roles');
    const last = await this.prisma.employee.findFirst({ where: { code: { startsWith: 'SIR-' } }, orderBy: { code: 'desc' }, select: { code: true } });
    const next = (last ? Number(last.code.slice(4)) : 0) + 1;
    const code = `SIR-${String(next).padStart(4, '0')}`;
    const emp = await this.prisma.employee.create({
      data: { ...(this.toData(dto) as Prisma.EmployeeUncheckedCreateInput), code, status: dto.status ?? 'ONBOARDING' },
      select: RESTRICTED_SELECT,
    });
    await this.audit.log(actor.id, 'create', 'Employee', emp.id, { code });
    return emp;
  }

  async update(actor: Actor, ability: AppAbility, id: string, dto: EmployeeDto) {
    const emp = await this.prisma.employee.findUnique({ where: { id }, select: { id: true, locationId: true, role: true } });
    if (!emp) throw new NotFoundException();
    // Only super admins edit a super admin's record (their email, status, location...).
    if (emp.role === 'SUPER_ADMIN' && actor.role !== 'SUPER_ADMIN' && emp.id !== actor.id) throw new ForbiddenException('Only a super admin can edit this person');
    // HR (in scope for this person's location) may edit everything; others only their own contact details.
    const isHrEdit = canDo(ability, 'create', 'Employee', { locationId: emp.locationId });
    if (!isHrEdit) {
      assertCan(ability, 'update', 'Employee', { id: emp.id, locationId: emp.locationId });
      const blocked = sentKeys(dto).filter((k) => !SELF_EDITABLE.includes(k as keyof EmployeeDto));
      if (blocked.length) throw new BadRequestException(`You can't change: ${blocked.join(', ')}. Ask HR.`);
    } else if (dto.locationId !== undefined && dto.locationId !== emp.locationId) {
      // HR limited to one location may not move someone to a location they don't manage.
      assertCan(ability, 'create', 'Employee', { locationId: dto.locationId });
    }
    const before = dto.role ? await this.access.assertRoleChange(actor, id, dto.role) : null;
    if (dto.managerId === id) throw new BadRequestException('Someone cannot report to themselves');
    if (dto.status === 'EXITED') await this.keepOneSuperAdmin(id);
    const updated = await this.prisma.employee.update({ where: { id }, data: this.toData(dto) as Prisma.EmployeeUncheckedUpdateInput, select: RESTRICTED_SELECT });
    await this.audit.log(actor.id, 'update', 'Employee', id, { fields: sentKeys(dto) });
    if (before) await this.access.roleChanged(actor, id, before.role, updated.role);
    return updated;
  }

  /** Refuses to demote or exit the last active super admin, so nobody is locked out of access control. */
  private async keepOneSuperAdmin(id: string) {
    const target = await this.prisma.employee.findUniqueOrThrow({ where: { id }, select: { role: true, status: true } });
    if (target.role !== 'SUPER_ADMIN' || target.status === 'EXITED') return;
    const others = await this.prisma.employee.count({ where: { role: 'SUPER_ADMIN', status: { not: 'EXITED' }, id: { not: id } } });
    if (!others) throw new BadRequestException('This is the last super admin. Make someone else super admin first.');
  }

  async lookups() {
    const [departments, locations, leaveTypes, managers] = await Promise.all([
      this.prisma.department.findMany({ orderBy: { name: 'asc' } }),
      this.prisma.location.findMany({ orderBy: { name: 'asc' }, select: { id: true, name: true } }),
      this.prisma.leaveType.findMany({ where: { active: true }, orderBy: { code: 'asc' } }),
      this.prisma.employee.findMany({ where: { status: { not: 'EXITED' } }, select: { id: true, fullName: true }, orderBy: { fullName: 'asc' } }),
    ]);
    return { departments, locations, leaveTypes, managers };
  }
}

@Controller()
export class EmployeesController {
  constructor(private svc: EmployeesService) {}

  @Get('employees')
  list(@Query('q') q?: string, @Query('departmentId') departmentId?: string) {
    return this.svc.list(q, departmentId);
  }

  @Get('employees/:id')
  get(@CurrentAbility() ability: AppAbility, @Param('id') id: string) {
    return this.svc.get(ability, id);
  }

  @Post('employees')
  create(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Body() dto: EmployeeDto) {
    return this.svc.create(actor, ability, dto);
  }

  @Patch('employees/:id')
  update(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string, @Body() dto: EmployeeDto) {
    return this.svc.update(actor, ability, id, dto);
  }

  @Get('lookups')
  lookups() {
    return this.svc.lookups();
  }
}

@Module({
  controllers: [EmployeesController],
  providers: [EmployeesService],
})
export class EmployeesModule {}
