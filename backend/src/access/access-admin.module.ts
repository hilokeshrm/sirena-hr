import { BadRequestException, Body, Controller, Delete, ForbiddenException, Get, Injectable, Module, NotFoundException, Param, Patch, Post, Put } from '@nestjs/common';
import { Role } from '@prisma/client';
import { IsBoolean, IsEnum } from 'class-validator';
import { CurrentActor } from '../auth/auth.guard';
import { AuditService } from '../common/audit.service';
import { PrismaService } from '../prisma/prisma.service';
import { AccessService, Actor, effectivePermissions } from './access.service';
import { defaultPermissionsFor, describeEffect, EDITABLE_ROLES, isPermissionKey, PERMISSION_KEYS, PERMISSIONS, PermissionKey } from './permissions';

class RoleGrantDto {
  @IsBoolean() enabled!: boolean;
}

class OverrideDto {
  @IsBoolean() granted!: boolean;
}

class RoleDto {
  @IsEnum(Role) role!: Role;
}

/** Super admin only: which role (or person) holds which permission. */
@Injectable()
export class AccessAdminService {
  constructor(private prisma: PrismaService, private access: AccessService, private audit: AuditService) {}

  private check(actor: Actor) {
    if (actor.role !== 'SUPER_ADMIN') throw new ForbiddenException('Only a super admin can change access');
  }

  private permission(key: string): PermissionKey {
    if (!isPermissionKey(key)) throw new NotFoundException(`Unknown permission ${key}`);
    return key;
  }

  private role(role: string): Role {
    if (role === 'SUPER_ADMIN') throw new BadRequestException('Super admins always have full access');
    if (!EDITABLE_ROLES.includes(role as Role)) throw new NotFoundException(`Unknown role ${role}`);
    return role as Role;
  }

  async matrix(actor: Actor) {
    this.check(actor);
    const [rows, overrides] = await Promise.all([
      this.prisma.rolePermission.findMany(),
      this.prisma.permissionOverride.findMany({
        include: { employee: { select: { id: true, code: true, fullName: true, role: true, status: true } } },
        orderBy: [{ employee: { fullName: 'asc' } }, { permission: 'asc' }],
      }),
    ]);
    const grants = Object.fromEntries(EDITABLE_ROLES.map((r) => [r, rows.filter((g) => g.role === r && isPermissionKey(g.permission)).map((g) => g.permission)]));
    const defaults = Object.fromEntries(EDITABLE_ROLES.map((r) => [r, defaultPermissionsFor(r)]));
    return {
      permissions: PERMISSIONS.map(({ key, group, label, description }) => ({ key, group, label, description })),
      roles: EDITABLE_ROLES,
      grants,
      defaults,
      overrides: overrides
        .filter((o) => isPermissionKey(o.permission))
        .map((o) => ({ employee: o.employee, permission: o.permission, granted: o.granted, updatedAt: o.updatedAt })),
    };
  }

  async setRoleGrant(actor: Actor, roleParam: string, key: string, enabled: boolean) {
    this.check(actor);
    const role = this.role(roleParam);
    const permission = this.permission(key);
    if (enabled) {
      await this.prisma.rolePermission.upsert({
        where: { role_permission: { role, permission } },
        create: { role, permission, updatedBy: actor.id },
        update: { updatedBy: actor.id },
      });
    } else {
      await this.prisma.rolePermission.deleteMany({ where: { role, permission } });
    }
    this.access.invalidate();
    await this.audit.log(actor.id, enabled ? 'grant' : 'revoke', 'RolePermission', `${role}:${permission}`, { role, permission });
    return this.matrix(actor);
  }

  /** Puts every role back to the built-in defaults. Personal overrides are kept. */
  async resetRoles(actor: Actor) {
    this.check(actor);
    await this.prisma.$transaction([
      this.prisma.rolePermission.deleteMany({}),
      this.prisma.rolePermission.createMany({
        data: EDITABLE_ROLES.flatMap((role) => defaultPermissionsFor(role).map((permission) => ({ role, permission, updatedBy: actor.id }))),
      }),
    ]);
    this.access.invalidate();
    await this.audit.log(actor.id, 'reset', 'RolePermission');
    return this.matrix(actor);
  }

  /** Everyone still working here, with their role and any personal overrides. */
  async people(actor: Actor) {
    this.check(actor);
    const rows = await this.prisma.employee.findMany({
      where: { status: { not: 'EXITED' } },
      orderBy: { fullName: 'asc' },
      select: {
        id: true, code: true, fullName: true, email: true, role: true, status: true, designation: true,
        department: { select: { id: true, name: true } }, location: { select: { id: true, name: true } },
        permissionOverrides: { select: { permission: true, granted: true } },
      },
    });
    return rows.map(({ permissionOverrides, ...e }) => ({ ...e, overrides: permissionOverrides.filter((o) => isPermissionKey(o.permission)) }));
  }

  /** One person's role, overrides and, for every permission, whether they have it and what that means. */
  async person(actor: Actor, employeeId: string) {
    this.check(actor);
    const emp = await this.prisma.employee.findUnique({
      where: { id: employeeId },
      select: { id: true, code: true, fullName: true, role: true, status: true, permissionOverrides: { select: { permission: true, granted: true } } },
    });
    if (!emp) throw new NotFoundException();
    const roleGrants = (await this.prisma.rolePermission.findMany({ where: { role: emp.role } })).map((g) => g.permission).filter(isPermissionKey);
    const overrides = emp.permissionOverrides.filter((o) => isPermissionKey(o.permission)) as { permission: PermissionKey; granted: boolean }[];
    const effective = effectivePermissions(emp.role, roleGrants, overrides.map((o) => [o.permission, o.granted]));
    const superAdmin = emp.role === 'SUPER_ADMIN';
    return {
      employee: { id: emp.id, code: emp.code, fullName: emp.fullName, role: emp.role, status: emp.status },
      roleGrants: superAdmin ? [] : roleGrants,
      overrides: superAdmin ? [] : overrides,
      effective,
      permissions: PERMISSION_KEYS.map((key) => {
        const has = effective.includes(key);
        const override = superAdmin ? undefined : overrides.find((o) => o.permission === key);
        return {
          key,
          has,
          fromRole: superAdmin || roleGrants.includes(key),
          overridden: !!override,
          effect: superAdmin ? 'Full access (super admin).' : describeEffect(key, emp.role, has),
        };
      }),
    };
  }

  async setRole(actor: Actor, employeeId: string, role: Role) {
    this.check(actor);
    const before = await this.access.assertRoleChange(actor, employeeId, role);
    await this.prisma.employee.update({ where: { id: employeeId }, data: { role } });
    await this.access.roleChanged(actor, employeeId, before.role, role);
    return this.person(actor, employeeId);
  }

  async setOverride(actor: Actor, employeeId: string, key: string, granted: boolean | null) {
    this.check(actor);
    const permission = this.permission(key);
    const emp = await this.prisma.employee.findUnique({ where: { id: employeeId }, select: { id: true, role: true } });
    if (!emp) throw new NotFoundException();
    if (emp.role === 'SUPER_ADMIN' && granted !== null) throw new BadRequestException('Super admins always have full access');
    if (employeeId === actor.id) throw new BadRequestException('You can’t change your own access');
    if (granted === null) {
      await this.prisma.permissionOverride.deleteMany({ where: { employeeId, permission } });
    } else {
      await this.prisma.permissionOverride.upsert({
        where: { employeeId_permission: { employeeId, permission } },
        create: { employeeId, permission, granted, updatedBy: actor.id },
        update: { granted, updatedBy: actor.id },
      });
    }
    this.access.invalidate();
    const action = granted === null ? 'clear-override' : granted ? 'grant' : 'revoke';
    await this.audit.log(actor.id, action, 'PermissionOverride', `${employeeId}:${permission}`, { employeeId, permission });
    return this.person(actor, employeeId);
  }
}

@Controller('access')
export class AccessAdminController {
  constructor(private svc: AccessAdminService) {}

  @Get('permissions')
  matrix(@CurrentActor() actor: Actor) {
    return this.svc.matrix(actor);
  }

  @Put('roles/:role/:permission')
  setRoleGrant(@CurrentActor() actor: Actor, @Param('role') role: string, @Param('permission') permission: string, @Body() dto: RoleGrantDto) {
    return this.svc.setRoleGrant(actor, role, permission, dto.enabled);
  }

  @Post('roles/reset')
  resetRoles(@CurrentActor() actor: Actor) {
    return this.svc.resetRoles(actor);
  }

  @Get('people')
  people(@CurrentActor() actor: Actor) {
    return this.svc.people(actor);
  }

  @Patch('people/:id')
  setRole(@CurrentActor() actor: Actor, @Param('id') id: string, @Body() dto: RoleDto) {
    return this.svc.setRole(actor, id, dto.role);
  }

  @Get('people/:id')
  person(@CurrentActor() actor: Actor, @Param('id') id: string) {
    return this.svc.person(actor, id);
  }

  @Put('people/:id/:permission')
  setOverride(@CurrentActor() actor: Actor, @Param('id') id: string, @Param('permission') permission: string, @Body() dto: OverrideDto) {
    return this.svc.setOverride(actor, id, permission, dto.granted);
  }

  @Delete('people/:id/:permission')
  clearOverride(@CurrentActor() actor: Actor, @Param('id') id: string, @Param('permission') permission: string) {
    return this.svc.setOverride(actor, id, permission, null);
  }
}

@Module({
  controllers: [AccessAdminController],
  providers: [AccessAdminService],
})
export class AccessAdminModule {}
