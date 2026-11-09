import { BadRequestException, Body, Controller, ForbiddenException, Get, HttpCode, HttpException, HttpStatus, Injectable, Ip, Module, NotFoundException, Param, Post, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { JwtModule, JwtService } from '@nestjs/jwt';
import { FoodPref } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { randomBytes } from 'node:crypto';
import { IsDateString, IsEmail, IsEnum, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { AccessService, Actor, AppAbility, assertCan, canDo } from '../access/access.service';
import { AuditService } from '../common/audit.service';
import { toDbDate } from '../common/dates';
import { PrismaService } from '../prisma/prisma.service';
import { AllowTemporaryPassword, AuthGuard, CurrentAbility, CurrentActor, Public } from './auth.guard';
import { checkedJwtSecret, inviteProblem } from './auth-rules';
import { LoginLimiter } from './login-limiter';
import { PASSWORD_MIN, passwordProblem } from './password-policy';

class LoginDto {
  @IsEmail() @MaxLength(254) email!: string;
  @IsString() @MaxLength(256) password!: string;
}

class ChangePasswordDto {
  @IsString() @MaxLength(256) currentPassword!: string;
  @IsString() @MinLength(PASSWORD_MIN) @MaxLength(256) newPassword!: string;
}

class CreateInviteDto {
  @IsString() employeeId!: string;
}

class AcceptInviteDto {
  @IsString() @MinLength(PASSWORD_MIN) @MaxLength(256) password!: string;
  @IsOptional() @IsString() @MaxLength(100) preferredName?: string;
  @IsOptional() @IsString() @MaxLength(30) phone?: string;
  @IsOptional() @IsDateString() dateOfBirth?: string;
  @IsOptional() @IsEnum(FoodPref) foodPref?: FoodPref;
  @IsOptional() @IsString() @MaxLength(100) emergencyName?: string;
  @IsOptional() @IsString() @MaxLength(50) emergencyRelation?: string;
  @IsOptional() @IsString() @MaxLength(30) emergencyPhone?: string;
}

const TOO_MANY = 'Too many attempts. Try again in 15 minutes.';
// Compared against when the email is unknown, so a wrong email takes as long as a wrong password.
const DUMMY_HASH = bcrypt.hashSync('not-a-real-password', 12);

@Injectable()
export class AuthService {
  private limiter = new LoginLimiter();
  private changeLimiter = new LoginLimiter();

  constructor(private prisma: PrismaService, private jwt: JwtService, private audit: AuditService, private access: AccessService) {}

  private issueToken(employeeId: string) {
    return this.jwt.signAsync({ sub: employeeId });
  }

  async login(email: string, password: string, ip = '') {
    const key = email.toLowerCase();
    if (this.limiter.isLocked(key, ip)) throw new HttpException(TOO_MANY, HttpStatus.TOO_MANY_REQUESTS);

    const emp = await this.prisma.employee.findUnique({ where: { email: key } });
    const matches = await bcrypt.compare(password, emp?.passwordHash ?? DUMMY_HASH);
    const ok = matches && !!emp?.passwordHash && emp.status !== 'EXITED';
    if (!ok || !emp) {
      if (this.limiter.fail(key, ip)) await this.audit.log(emp?.id ?? null, 'login-locked', 'Employee', emp?.id, { email: key, ip });
      throw new UnauthorizedException('Wrong email or password');
    }
    this.limiter.succeed(key);
    await this.audit.log(emp.id, 'login', 'Employee', emp.id, { ip });
    return { accessToken: await this.issueToken(emp.id), employeeId: emp.id };
  }

  /** Changes the password, ends every other session, and returns a fresh token for this one. */
  async changePassword(actor: Actor, dto: ChangePasswordDto, ip = '') {
    if (this.changeLimiter.isLocked(actor.id, ip)) throw new HttpException(TOO_MANY, HttpStatus.TOO_MANY_REQUESTS);
    const emp = await this.prisma.employee.findUniqueOrThrow({ where: { id: actor.id } });
    if (!emp.passwordHash || !(await bcrypt.compare(dto.currentPassword, emp.passwordHash))) {
      if (this.changeLimiter.fail(actor.id, ip)) await this.audit.log(actor.id, 'change-password-locked', 'Employee', actor.id, { ip });
      throw new BadRequestException('Current password is wrong');
    }
    this.changeLimiter.succeed(actor.id);
    if (dto.newPassword === dto.currentPassword) throw new BadRequestException('Choose a new password that is different from the current one');
    const problem = passwordProblem(dto.newPassword, emp);
    if (problem) throw new BadRequestException(problem);
    await this.prisma.employee.update({ where: { id: actor.id }, data: { passwordHash: await bcrypt.hash(dto.newPassword, 12), mustChangePassword: false } });
    await this.access.revokeSessions(actor.id);
    await this.audit.log(actor.id, 'change-password', 'Employee', actor.id, { ip });
    return { ok: true, accessToken: await this.issueToken(actor.id) };
  }

  async createInvite(actor: Actor, ability: AppAbility, employeeId: string) {
    assertCan(ability, 'create', 'Invite');
    const emp = await this.prisma.employee.findUnique({ where: { id: employeeId } });
    if (!emp) throw new NotFoundException();
    const problem = inviteProblem(actor, emp);
    if (problem) throw new ForbiddenException(problem);
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
    const emp = await this.prisma.employee.findUniqueOrThrow({ where: { id: inv.employeeId }, select: { email: true, fullName: true } });
    const problem = passwordProblem(password, emp);
    if (problem) throw new BadRequestException(problem);
    await this.prisma.$transaction([
      this.prisma.employee.update({
        where: { id: inv.employeeId },
        data: { ...rest, dateOfBirth: dateOfBirth ? toDbDate(dateOfBirth.slice(0, 10)) : undefined, passwordHash: await bcrypt.hash(password, 12), mustChangePassword: false, status: 'ACTIVE' },
      }),
      this.prisma.invite.update({ where: { token }, data: { usedAt: new Date() } }),
    ]);
    // Any session from before (e.g. before a super admin re-invited them) ends.
    await this.access.revokeSessions(inv.employeeId);
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

  @AllowTemporaryPassword() @Post('auth/change-password') @HttpCode(200)
  changePassword(@CurrentActor() actor: Actor, @Body() dto: ChangePasswordDto, @Ip() ip: string) {
    return this.auth.changePassword(actor, dto, ip);
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
  @AllowTemporaryPassword() @Get('me')
  async me(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility) {
    const me = await this.prisma.employee.findUniqueOrThrow({
      where: { id: actor.id },
      select: {
        id: true, code: true, email: true, role: true, fullName: true, preferredName: true, designation: true, foodPref: true,
        workMode: true, phone: true, joinedOn: true, mustChangePassword: true,
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
        manageAccess: actor.role === 'SUPER_ADMIN',
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
        secret: checkedJwtSecret(cfg.get<string>('JWT_SECRET')),
        signOptions: { expiresIn: cfg.get('JWT_EXPIRES_IN', '12h'), algorithm: 'HS256' },
        verifyOptions: { algorithms: ['HS256'] },
      }),
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, { provide: APP_GUARD, useClass: AuthGuard }],
})
export class AuthModule {}
