import { BadRequestException, Body, Controller, Get, HttpCode, Injectable, Ip, Module, NotFoundException, Param, Post, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { JwtModule, JwtService } from '@nestjs/jwt';
import { FoodPref } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { randomBytes } from 'node:crypto';
import { IsDateString, IsEmail, IsEnum, IsOptional, IsString, MinLength } from 'class-validator';
import { Actor, AppAbility, assertCan, canDo } from '../access/access.service';
import { AuditService } from '../common/audit.service';
import { toDbDate } from '../common/dates';
import { PrismaService } from '../prisma/prisma.service';
import { AuthGuard, CurrentAbility, CurrentActor, Public } from './auth.guard';

class LoginDto {
  @IsEmail() email!: string;
  @IsString() password!: string;
}

class ChangePasswordDto {
  @IsString() currentPassword!: string;
  @IsString() @MinLength(10) newPassword!: string;
}

class CreateInviteDto {
  @IsString() employeeId!: string;
}

class AcceptInviteDto {
  @IsString() @MinLength(10) password!: string;
  @IsOptional() @IsString() preferredName?: string;
  @IsOptional() @IsString() phone?: string;
  @IsOptional() @IsDateString() dateOfBirth?: string;
  @IsOptional() @IsEnum(FoodPref) foodPref?: FoodPref;
  @IsOptional() @IsString() emergencyName?: string;
  @IsOptional() @IsString() emergencyRelation?: string;
  @IsOptional() @IsString() emergencyPhone?: string;
}

const MAX_FAILS = 5;
const LOCK_MS = 15 * 60 * 1000;
// Per source IP, so one address can't try a few passwords on every account.
const MAX_IP_FAILS = 30;

@Injectable()
export class AuthService {
  private fails = new Map<string, { count: number; until: number }>();
  private ipFails = new Map<string, { count: number; since: number }>();

  constructor(private prisma: PrismaService, private jwt: JwtService, private audit: AuditService) {}

  async login(email: string, password: string, ip = '') {
    const key = email.toLowerCase();
    const f = this.fails.get(key);
    if (f && f.until > Date.now()) throw new UnauthorizedException('Too many attempts. Try again in 15 minutes.');
    const fi = this.ipFails.get(ip);
    if (fi && fi.since > Date.now() - LOCK_MS && fi.count >= MAX_IP_FAILS) throw new UnauthorizedException('Too many attempts. Try again in 15 minutes.');

    const emp = await this.prisma.employee.findUnique({ where: { email: key } });
    const ok = !!emp?.passwordHash && emp.status !== 'EXITED' && (await bcrypt.compare(password, emp.passwordHash));
    if (!ok || !emp) {
      const count = (f?.count ?? 0) + 1;
      this.fails.set(key, { count, until: count >= MAX_FAILS ? Date.now() + LOCK_MS : 0 });
      const fresh = !fi || fi.since <= Date.now() - LOCK_MS;
      this.ipFails.set(ip, { count: fresh ? 1 : fi.count + 1, since: fresh ? Date.now() : fi.since });
      throw new UnauthorizedException('Wrong email or password');
    }
    this.fails.delete(key);
    await this.audit.log(emp.id, 'login', 'Employee', emp.id);
    return { accessToken: await this.jwt.signAsync({ sub: emp.id }), employeeId: emp.id };
  }

  async changePassword(actor: Actor, dto: ChangePasswordDto) {
    const emp = await this.prisma.employee.findUniqueOrThrow({ where: { id: actor.id } });
    if (!emp.passwordHash || !(await bcrypt.compare(dto.currentPassword, emp.passwordHash))) {
      throw new BadRequestException('Current password is wrong');
    }
    await this.prisma.employee.update({ where: { id: actor.id }, data: { passwordHash: await bcrypt.hash(dto.newPassword, 12) } });
    await this.audit.log(actor.id, 'change-password', 'Employee', actor.id);
    return { ok: true };
  }

  async createInvite(actor: Actor, ability: AppAbility, employeeId: string) {
    assertCan(ability, 'create', 'Invite');
    const emp = await this.prisma.employee.findUnique({ where: { id: employeeId } });
    if (!emp) throw new NotFoundException();
    const token = randomBytes(24).toString('base64url');
    await this.prisma.invite.upsert({
      where: { employeeId },
      create: { token, employeeId, invitedBy: actor.id, expiresAt: new Date(Date.now() + 7 * 864e5) },
      update: { token, invitedBy: actor.id, expiresAt: new Date(Date.now() + 7 * 864e5), usedAt: null },
    });
    await this.audit.log(actor.id, 'invite', 'Employee', employeeId);
    // The invite link is sent by email in production; returned here for HR to share.
    return { token, path: `/signup/${token}` };
  }

  private async validInvite(token: string) {
    const inv = await this.prisma.invite.findUnique({ where: { token } });
    if (!inv || inv.usedAt || inv.expiresAt < new Date()) throw new NotFoundException('This invite link is invalid or has expired');
    return inv;
  }

  async inviteDetails(token: string) {
    const inv = await this.validInvite(token);
    const emp = await this.prisma.employee.findUniqueOrThrow({
      where: { id: inv.employeeId },
      select: { fullName: true, email: true, designation: true, joinedOn: true, department: { select: { name: true } }, location: { select: { name: true } } },
    });
    const by = inv.invitedBy ? await this.prisma.employee.findUnique({ where: { id: inv.invitedBy }, select: { fullName: true } }) : null;
    return { ...emp, invitedBy: by?.fullName ?? null, expiresAt: inv.expiresAt };
  }

  async acceptInvite(token: string, dto: AcceptInviteDto) {
    const inv = await this.validInvite(token);
    const { password, dateOfBirth, ...rest } = dto;
    await this.prisma.$transaction([
      this.prisma.employee.update({
        where: { id: inv.employeeId },
        data: { ...rest, dateOfBirth: dateOfBirth ? toDbDate(dateOfBirth.slice(0, 10)) : undefined, passwordHash: await bcrypt.hash(password, 12), status: 'ACTIVE' },
      }),
      this.prisma.invite.update({ where: { token }, data: { usedAt: new Date() } }),
    ]);
    await this.audit.log(inv.employeeId, 'accept-invite', 'Employee', inv.employeeId);
    return { ok: true };
  }
}

@Controller()
export class AuthController {
  constructor(private auth: AuthService, private prisma: PrismaService) {}

  @Public() @Post('auth/login') @HttpCode(200)
  login(@Body() dto: LoginDto, @Ip() ip: string) {
    return this.auth.login(dto.email, dto.password, ip);
  }

  @Post('auth/change-password') @HttpCode(200)
  changePassword(@CurrentActor() actor: Actor, @Body() dto: ChangePasswordDto) {
    return this.auth.changePassword(actor, dto);
  }

  @Post('auth/invites')
  invite(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Body() dto: CreateInviteDto) {
    return this.auth.createInvite(actor, ability, dto.employeeId);
  }

  @Public() @Get('auth/invites/:token')
  inviteDetails(@Param('token') token: string) {
    return this.auth.inviteDetails(token);
  }

  @Public() @Post('auth/invites/:token/accept') @HttpCode(200)
  accept(@Param('token') token: string, @Body() dto: AcceptInviteDto) {
    return this.auth.acceptInvite(token, dto);
  }

  /** The signed-in person plus what the app should show them. */
  @Get('me')
  async me(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility) {
    const me = await this.prisma.employee.findUniqueOrThrow({
      where: { id: actor.id },
      select: {
        id: true, code: true, email: true, role: true, fullName: true, preferredName: true, designation: true, foodPref: true,
        workMode: true, phone: true, joinedOn: true,
        department: { select: { id: true, name: true } }, location: { select: { id: true, name: true } },
        manager: { select: { id: true, fullName: true } },
      },
    });
    return {
      ...me,
      permissions: {
        isManager: actor.managerOf.length > 0,
        approveLeave: actor.managerOf.length > 0 || canDo(ability, 'approve', 'LeaveRequest', { status: 'PENDING_HR', employeeLocationId: actor.locationId }),
        manageEmployees: canDo(ability, 'create', 'Employee', { locationId: actor.locationId }),
        manageLeaveRules: canDo(ability, 'manage', 'LeaveType'),
        managePolicies: canDo(ability, 'manage', 'Policy'),
        viewMealReport: canDo(ability, 'read', 'MealReport'),
        viewAllAttendance: canDo(ability, 'read', 'Attendance', { employeeId: '_', employeeLocationId: actor.locationId }),
        admin: actor.role === 'SUPER_ADMIN',
      },
      projects: actor.projects,
    };
  }
}

@Module({
  imports: [
    JwtModule.registerAsync({
      global: true,
      inject: [ConfigService],
      useFactory: (cfg: ConfigService) => ({
        secret: cfg.getOrThrow<string>('JWT_SECRET'),
        signOptions: { expiresIn: cfg.get('JWT_EXPIRES_IN', '12h') },
      }),
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, { provide: APP_GUARD, useClass: AuthGuard }],
})
export class AuthModule {}
