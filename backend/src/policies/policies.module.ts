import { BadRequestException, Body, Controller, Get, HttpCode, Injectable, Module, NotFoundException, Param, Post } from '@nestjs/common';
import { IsBoolean, IsDateString, IsOptional, IsString } from 'class-validator';
import { Actor, AppAbility, assertCan } from '../access/access.service';
import { AuditService, NotifyService } from '../common/audit.service';
import { PrismaService } from '../prisma/prisma.service';
import { CurrentAbility, CurrentActor } from '../auth/auth.guard';

class PolicyDto {
  @IsString() title!: string;
  @IsString() category!: string;
  @IsString() body!: string;
  @IsOptional() @IsBoolean() requireAck?: boolean;
  @IsOptional() @IsString() locationId?: string;
  @IsOptional() @IsString() changeSummary?: string;
}

class VersionDto {
  @IsString() body!: string;
  @IsOptional() @IsString() changeSummary?: string;
}

class PublishDto {
  @IsOptional() @IsDateString() ackDueAt?: string;
}

@Injectable()
export class PoliciesService {
  constructor(private prisma: PrismaService, private audit: AuditService, private notify: NotifyService) {}

  private async audienceFor(locationId: string | null) {
    return this.prisma.employee.findMany({
      where: { status: { in: ['ACTIVE', 'ON_NOTICE', 'ONBOARDING'] }, ...(locationId ? { locationId } : {}) },
      select: { id: true, fullName: true },
    });
  }

  /** Published policies for me, with whether I still need to acknowledge the latest version. */
  async list(actor: Actor) {
    const policies = await this.prisma.policy.findMany({
      where: { OR: [{ locationId: null }, { locationId: actor.locationId }] },
      include: {
        versions: {
          where: { publishedAt: { not: null } },
          orderBy: { version: 'desc' },
          take: 1,
          include: { acks: { where: { employeeId: actor.id } } },
        },
      },
      orderBy: { title: 'asc' },
    });
    return policies
      .filter((p) => p.versions.length)
      .map((p) => {
        const v = p.versions[0];
        return {
          id: p.id, title: p.title, category: p.category, requireAck: p.requireAck,
          version: v.version, versionId: v.id, publishedAt: v.publishedAt, ackDueAt: v.ackDueAt, changeSummary: v.changeSummary,
          needsAck: p.requireAck && v.acks.length === 0,
          ackedAt: v.acks[0]?.at ?? null,
        };
      });
  }

  async get(actor: Actor, id: string) {
    const p = await this.prisma.policy.findUnique({
      where: { id },
      include: { versions: { orderBy: { version: 'desc' }, include: { acks: { where: { employeeId: actor.id } } } } },
    });
    if (!p) throw new NotFoundException();
    const published = p.versions.find((v) => v.publishedAt);
    if (!published) throw new NotFoundException();
    return {
      id: p.id, title: p.title, category: p.category, requireAck: p.requireAck,
      version: published.version, versionId: published.id, body: published.body, changeSummary: published.changeSummary,
      publishedAt: published.publishedAt, ackDueAt: published.ackDueAt,
      ackedAt: published.acks[0]?.at ?? null,
    };
  }

  async ack(actor: Actor, versionId: string) {
    const v = await this.prisma.policyVersion.findUnique({ where: { id: versionId } });
    if (!v || !v.publishedAt) throw new NotFoundException();
    const row = await this.prisma.policyAck.upsert({
      where: { versionId_employeeId: { versionId, employeeId: actor.id } },
      create: { versionId, employeeId: actor.id },
      update: {},
    });
    await this.audit.log(actor.id, 'ack', 'PolicyVersion', versionId);
    return row;
  }

  // ── HR ──

  async adminList(ability: AppAbility) {
    assertCan(ability, 'manage', 'Policy');
    const rows = await this.prisma.policy.findMany({
      include: { versions: { orderBy: { version: 'desc' }, take: 1, include: { _count: { select: { acks: true } } } } },
      orderBy: { title: 'asc' },
    });
    return Promise.all(
      rows.map(async (p) => {
        const v = p.versions[0];
        const audience = v?.publishedAt && p.requireAck ? (await this.audienceFor(p.locationId)).length : 0;
        return {
          id: p.id, title: p.title, category: p.category, requireAck: p.requireAck, locationId: p.locationId,
          version: v?.version ?? null, versionId: v?.id ?? null, status: v?.publishedAt ? 'PUBLISHED' : 'DRAFT',
          acked: v?._count.acks ?? 0, audience,
        };
      }),
    );
  }

  async create(actor: Actor, ability: AppAbility, dto: PolicyDto) {
    assertCan(ability, 'manage', 'Policy');
    const p = await this.prisma.policy.create({
      data: {
        title: dto.title, category: dto.category, requireAck: dto.requireAck ?? true, locationId: dto.locationId,
        versions: { create: { version: 1, body: dto.body, changeSummary: dto.changeSummary } },
      },
      include: { versions: true },
    });
    await this.audit.log(actor.id, 'create', 'Policy', p.id);
    return p;
  }

  async newVersion(actor: Actor, ability: AppAbility, policyId: string, dto: VersionDto) {
    assertCan(ability, 'manage', 'PolicyVersion');
    const last = await this.prisma.policyVersion.findFirst({ where: { policyId }, orderBy: { version: 'desc' } });
    if (!last) throw new NotFoundException();
    // A draft that hasn't been published yet is edited in place.
    if (!last.publishedAt) return this.prisma.policyVersion.update({ where: { id: last.id }, data: dto });
    const v = await this.prisma.policyVersion.create({ data: { policyId, version: last.version + 1, ...dto } });
    await this.audit.log(actor.id, 'new-version', 'Policy', policyId, { version: v.version });
    return v;
  }

  async publish(actor: Actor, ability: AppAbility, versionId: string, dto: PublishDto) {
    assertCan(ability, 'manage', 'PolicyVersion');
    const v = await this.prisma.policyVersion.findUnique({ where: { id: versionId }, include: { policy: true } });
    if (!v) throw new NotFoundException();
    if (v.publishedAt) throw new BadRequestException('Already published');
    const updated = await this.prisma.policyVersion.update({
      where: { id: versionId },
      data: { publishedAt: new Date(), ackDueAt: dto.ackDueAt ? new Date(dto.ackDueAt) : null },
    });
    const people = await this.audienceFor(v.policy.locationId);
    const verb = v.version > 1 ? 'was updated' : 'was published';
    await this.notify.send(people.map((p) => p.id), `${v.policy.title} ${verb}${v.policy.requireAck ? '. Please read and acknowledge.' : ''}`, `/policies/${v.policyId}`);
    await this.audit.log(actor.id, 'publish', 'PolicyVersion', versionId);
    return updated;
  }

  /** Who has and hasn't acknowledged a version. */
  async acks(ability: AppAbility, versionId: string) {
    assertCan(ability, 'manage', 'Policy');
    const v = await this.prisma.policyVersion.findUnique({ where: { id: versionId }, include: { policy: true, acks: true } });
    if (!v) throw new NotFoundException();
    const people = await this.audienceFor(v.policy.locationId);
    const done = new Map(v.acks.map((a) => [a.employeeId, a.at]));
    return {
      acked: people.filter((p) => done.has(p.id)).map((p) => ({ ...p, at: done.get(p.id) })),
      pending: people.filter((p) => !done.has(p.id)),
    };
  }

  async remind(actor: Actor, ability: AppAbility, versionId: string) {
    const { pending } = await this.acks(ability, versionId);
    const v = await this.prisma.policyVersion.findUniqueOrThrow({ where: { id: versionId }, include: { policy: true } });
    await this.notify.send(pending.map((p) => p.id), `Reminder: please acknowledge ${v.policy.title}`, `/policies/${v.policyId}`);
    await this.audit.log(actor.id, 'remind', 'PolicyVersion', versionId, { count: pending.length });
    return { reminded: pending.length };
  }
}

@Controller()
export class PoliciesController {
  constructor(private svc: PoliciesService, private prisma: PrismaService) {}

  @Get('policies')
  list(@CurrentActor() actor: Actor) {
    return this.svc.list(actor);
  }

  @Get('policies/admin')
  adminList(@CurrentAbility() ability: AppAbility) {
    return this.svc.adminList(ability);
  }

  @Get('policies/:id')
  get(@CurrentActor() actor: Actor, @Param('id') id: string) {
    return this.svc.get(actor, id);
  }

  @Post('policies')
  create(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Body() dto: PolicyDto) {
    return this.svc.create(actor, ability, dto);
  }

  @Post('policies/:id/versions')
  version(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string, @Body() dto: VersionDto) {
    return this.svc.newVersion(actor, ability, id, dto);
  }

  @Post('policy-versions/:id/publish') @HttpCode(200)
  publish(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string, @Body() dto: PublishDto) {
    return this.svc.publish(actor, ability, id, dto);
  }

  @Post('policy-versions/:id/ack') @HttpCode(200)
  ack(@CurrentActor() actor: Actor, @Param('id') id: string) {
    return this.svc.ack(actor, id);
  }

  @Get('policy-versions/:id/acks')
  acks(@CurrentAbility() ability: AppAbility, @Param('id') id: string) {
    return this.svc.acks(ability, id);
  }

  @Post('policy-versions/:id/remind') @HttpCode(200)
  remind(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string) {
    return this.svc.remind(actor, ability, id);
  }

  // ── Notifications ──

  @Get('notifications')
  notifications(@CurrentActor() actor: Actor) {
    return this.prisma.notification.findMany({ where: { employeeId: actor.id }, orderBy: { createdAt: 'desc' }, take: 50 });
  }

  @Post('notifications/:id/read') @HttpCode(200)
  async read(@CurrentActor() actor: Actor, @Param('id') id: string) {
    await this.prisma.notification.updateMany({ where: { id, employeeId: actor.id, readAt: null }, data: { readAt: new Date() } });
    return { ok: true };
  }

  @Post('notifications/read-all') @HttpCode(200)
  async readAll(@CurrentActor() actor: Actor) {
    const r = await this.prisma.notification.updateMany({ where: { employeeId: actor.id, readAt: null }, data: { readAt: new Date() } });
    return { read: r.count };
  }
}

@Module({
  controllers: [PoliciesController],
  providers: [PoliciesService],
})
export class PoliciesModule {}
