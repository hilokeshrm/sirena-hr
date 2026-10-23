import {
  BadRequestException, Body, Controller, Get, Injectable, Module, NotFoundException, Param, Patch, Post, Query, Res, StreamableFile,
  UnauthorizedException, UploadedFile, UseInterceptors,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { FileInterceptor } from '@nestjs/platform-express';
import { Priority, ProjectRole, ProjectStatus, Sensitivity, TaskStatus } from '@prisma/client';
import { IsDateString, IsEnum, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';
import type { Response } from 'express';
import { createReadStream, mkdirSync, writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import path from 'node:path';
import { AccessService, Actor, AppAbility, assertCan, canDo } from '../access/access.service';
import { AuditService, NotifyService } from '../common/audit.service';
import { fromDbDate, sentKeys, toDbDate } from '../common/dates';
import { PrismaService } from '../prisma/prisma.service';
import { CurrentAbility, CurrentActor, Public } from '../auth/auth.guard';

class ProjectDto {
  @IsOptional() @IsString() code?: string;
  @IsOptional() @IsString() name?: string;
  @IsOptional() @IsString() client?: string;
  @IsOptional() @IsEnum(ProjectStatus) status?: ProjectStatus;
  @IsOptional() @IsDateString() startDate?: string;
  @IsOptional() @IsDateString() endDate?: string;
  @IsOptional() @IsString() leadId?: string;
}

class MemberDto {
  @IsString() employeeId!: string;
  @IsOptional() @IsEnum(ProjectRole) role?: ProjectRole;
  @IsOptional() @IsInt() @Min(0) @Max(100) allocation?: number;
}

class TaskDto {
  @IsOptional() @IsString() title?: string;
  @IsOptional() @IsEnum(TaskStatus) status?: TaskStatus;
  @IsOptional() @IsEnum(Priority) priority?: Priority;
  @IsOptional() @IsString() assigneeId?: string;
  @IsOptional() @IsDateString() dueDate?: string;
}

class MilestoneDto {
  @IsString() name!: string;
  @IsOptional() @IsDateString() dueDate?: string;
}

class FolderDto {
  @IsString() name!: string;
  @IsOptional() @IsEnum(Sensitivity) sensitivity?: Sensitivity;
}

const MAX_UPLOAD = 50 * 1024 * 1024;

@Injectable()
export class ProjectsService {
  private filesDir: string;

  constructor(private prisma: PrismaService, private audit: AuditService, private notify: NotifyService, cfg: ConfigService) {
    this.filesDir = path.resolve(cfg.get('FILES_DIR', './storage/files'));
    mkdirSync(this.filesDir, { recursive: true });
  }

  private canSeeAll(actor: Actor) {
    return actor.role === 'SUPER_ADMIN' || actor.role === 'HR_ADMIN';
  }

  async list(actor: Actor) {
    const rows = await this.prisma.project.findMany({
      where: this.canSeeAll(actor) ? {} : { members: { some: { employeeId: actor.id } } },
      include: { lead: { select: { id: true, fullName: true } }, _count: { select: { members: true, tasks: true } } },
      orderBy: { name: 'asc' },
    });
    const done = await this.prisma.task.groupBy({ by: ['projectId'], where: { status: 'DONE', projectId: { in: rows.map((r) => r.id) } }, _count: true });
    return rows.map((p) => ({
      ...p,
      startDate: p.startDate ? fromDbDate(p.startDate) : null,
      endDate: p.endDate ? fromDbDate(p.endDate) : null,
      tasksDone: done.find((d) => d.projectId === p.id)?._count ?? 0,
      myRole: actor.projects.find((m) => m.projectId === p.id)?.role ?? null,
    }));
  }

  private async load(ability: AppAbility, actor: Actor, id: string) {
    const p = await this.prisma.project.findUnique({ where: { id } });
    if (!p) throw new NotFoundException();
    if (!this.canSeeAll(actor)) assertCan(ability, 'read', 'Project', { id });
    return p;
  }

  async get(actor: Actor, ability: AppAbility, id: string) {
    await this.load(ability, actor, id);
    const p = await this.prisma.project.findUniqueOrThrow({
      where: { id },
      include: {
        lead: { select: { id: true, fullName: true } },
        members: { include: { employee: { select: { id: true, fullName: true, designation: true } } } },
        milestones: { orderBy: { dueDate: 'asc' } },
      },
    });
    return {
      ...p,
      startDate: p.startDate ? fromDbDate(p.startDate) : null,
      endDate: p.endDate ? fromDbDate(p.endDate) : null,
      milestones: p.milestones.map((m) => ({ ...m, dueDate: m.dueDate ? fromDbDate(m.dueDate) : null })),
      canEdit: canDo(ability, 'update', 'Project', { id }),
    };
  }

  async create(actor: Actor, ability: AppAbility, dto: ProjectDto) {
    // Creating projects is an HR Admin / Super Admin task.
    if (!this.canSeeAll(actor)) throw new BadRequestException('Only admins can create projects');
    if (!dto.code || !dto.name) throw new BadRequestException('code and name are required');
    const p = await this.prisma.project.create({
      data: {
        code: dto.code, name: dto.name, client: dto.client, status: dto.status, leadId: dto.leadId,
        startDate: dto.startDate ? toDbDate(dto.startDate.slice(0, 10)) : undefined,
        endDate: dto.endDate ? toDbDate(dto.endDate.slice(0, 10)) : undefined,
        ...(dto.leadId ? { members: { create: { employeeId: dto.leadId, role: 'LEAD', allocation: 50 } } } : {}),
        folders: { create: [{ name: 'General' }, { name: 'Client docs', sensitivity: 'RESTRICTED' }] },
      },
    });
    await this.audit.log(actor.id, 'create', 'Project', p.id);
    return p;
  }

  async update(actor: Actor, ability: AppAbility, id: string, dto: ProjectDto) {
    if (!this.canSeeAll(actor)) assertCan(ability, 'update', 'Project', { id });
    const { startDate, endDate, ...rest } = dto;
    const p = await this.prisma.project.update({
      where: { id },
      data: { ...rest, ...(startDate ? { startDate: toDbDate(startDate.slice(0, 10)) } : {}), ...(endDate ? { endDate: toDbDate(endDate.slice(0, 10)) } : {}) },
    });
    await this.audit.log(actor.id, 'update', 'Project', id, { fields: sentKeys(dto) });
    return p;
  }

  async setMember(actor: Actor, ability: AppAbility, id: string, dto: MemberDto) {
    if (!this.canSeeAll(actor)) assertCan(ability, 'update', 'Project', { id });
    const m = await this.prisma.projectMember.upsert({
      where: { projectId_employeeId: { projectId: id, employeeId: dto.employeeId } },
      create: { projectId: id, employeeId: dto.employeeId, role: dto.role ?? 'MEMBER', allocation: dto.allocation ?? 100 },
      update: { role: dto.role, allocation: dto.allocation },
    });
    await this.audit.log(actor.id, 'set-member', 'Project', id, { ...dto });
    return m;
  }

  async addMilestone(actor: Actor, ability: AppAbility, id: string, dto: MilestoneDto) {
    if (!this.canSeeAll(actor)) assertCan(ability, 'update', 'Project', { id });
    return this.prisma.milestone.create({ data: { projectId: id, name: dto.name, dueDate: dto.dueDate ? toDbDate(dto.dueDate.slice(0, 10)) : undefined } });
  }

  async tasks(actor: Actor, ability: AppAbility, projectId: string, mine: boolean) {
    await this.load(ability, actor, projectId);
    const rows = await this.prisma.task.findMany({
      where: { projectId, ...(mine ? { assigneeId: actor.id } : {}) },
      include: { assignee: { select: { id: true, fullName: true } } },
      orderBy: [{ status: 'asc' }, { dueDate: 'asc' }],
    });
    return rows.map((t) => ({ ...t, dueDate: t.dueDate ? fromDbDate(t.dueDate) : null }));
  }

  /** My open tasks across every project (for the home screen). */
  async myTasks(actor: Actor) {
    const rows = await this.prisma.task.findMany({
      where: { assigneeId: actor.id, status: { not: 'DONE' } },
      include: { project: { select: { id: true, name: true } } },
      orderBy: { dueDate: 'asc' },
    });
    return rows.map((t) => ({ ...t, dueDate: t.dueDate ? fromDbDate(t.dueDate) : null }));
  }

  async createTask(actor: Actor, ability: AppAbility, projectId: string, dto: TaskDto) {
    if (!this.canSeeAll(actor)) assertCan(ability, 'create', 'Task', { projectId });
    if (!dto.title) throw new BadRequestException('title is required');
    const t = await this.prisma.task.create({
      data: { projectId, title: dto.title, status: dto.status, priority: dto.priority, assigneeId: dto.assigneeId, dueDate: dto.dueDate ? toDbDate(dto.dueDate.slice(0, 10)) : undefined },
    });
    if (dto.assigneeId && dto.assigneeId !== actor.id) await this.notify.send(dto.assigneeId, `New task: ${dto.title}`, `/projects/${projectId}`);
    return t;
  }

  async updateTask(actor: Actor, ability: AppAbility, id: string, dto: TaskDto) {
    const t = await this.prisma.task.findUnique({ where: { id } });
    if (!t) throw new NotFoundException();
    if (!this.canSeeAll(actor)) assertCan(ability, 'update', 'Task', { projectId: t.projectId });
    const { dueDate, ...rest } = dto;
    const updated = await this.prisma.task.update({ where: { id }, data: { ...rest, ...(dueDate ? { dueDate: toDbDate(dueDate.slice(0, 10)) } : {}) } });
    if (dto.assigneeId && dto.assigneeId !== t.assigneeId && dto.assigneeId !== actor.id) {
      await this.notify.send(dto.assigneeId, `Task assigned to you: ${updated.title}`, `/projects/${t.projectId}`);
    }
    return updated;
  }

  // ── Files ──

  private folderSubject(f: { projectId: string; sensitivity: Sensitivity }) {
    return { projectId: f.projectId, sensitivity: f.sensitivity };
  }

  async folders(actor: Actor, ability: AppAbility, projectId: string) {
    await this.load(ability, actor, projectId);
    const rows = await this.prisma.folder.findMany({
      where: { projectId },
      include: { files: { include: { uploadedBy: { select: { fullName: true } } }, orderBy: [{ name: 'asc' }, { version: 'desc' }] } },
      orderBy: { name: 'asc' },
    });
    return rows
      .filter((f) => this.canSeeAll(actor) || canDo(ability, 'read', 'Folder', this.folderSubject(f)))
      .map((f) => ({
        ...f,
        // Only the latest version of each file name is listed.
        files: f.files.filter((file, i, all) => all.findIndex((x) => x.name === file.name) === i),
      }));
  }

  async createFolder(actor: Actor, ability: AppAbility, projectId: string, dto: FolderDto) {
    if (!this.canSeeAll(actor)) assertCan(ability, 'update', 'Project', { id: projectId });
    return this.prisma.folder.create({ data: { projectId, name: dto.name, sensitivity: dto.sensitivity ?? 'NORMAL' } });
  }

  async upload(actor: Actor, ability: AppAbility, folderId: string, file: Express.Multer.File | undefined) {
    if (!file) throw new BadRequestException('Choose a file to upload');
    const folder = await this.prisma.folder.findUnique({ where: { id: folderId } });
    if (!folder) throw new NotFoundException();
    if (!this.canSeeAll(actor)) assertCan(ability, 'upload', 'Folder', this.folderSubject(folder));
    const name = path.basename(file.originalname).slice(0, 200);
    const prev = await this.prisma.projectFile.findFirst({ where: { folderId, name }, orderBy: { version: 'desc' } });
    const storageKey = `${folder.projectId}/${randomBytes(16).toString('hex')}`;
    mkdirSync(path.join(this.filesDir, folder.projectId), { recursive: true });
    writeFileSync(path.join(this.filesDir, storageKey), file.buffer);
    const row = await this.prisma.projectFile.create({
      data: { folderId, name, storageKey, size: file.size, mime: file.mimetype || 'application/octet-stream', version: (prev?.version ?? 0) + 1, uploadedById: actor.id },
    });
    await this.audit.log(actor.id, 'upload', 'ProjectFile', row.id, { name, version: row.version });
    return row;
  }

  async checkFileAccess(actor: Actor, ability: AppAbility, fileId: string) {
    const file = await this.prisma.projectFile.findUnique({ where: { id: fileId }, include: { folder: true } });
    if (!file) throw new NotFoundException();
    if (!this.canSeeAll(actor)) assertCan(ability, 'read', 'Folder', this.folderSubject(file.folder));
    return file;
  }

  async download(actor: Actor, ability: AppAbility, fileId: string, res: Response) {
    const file = await this.checkFileAccess(actor, ability, fileId);
    await this.audit.log(actor.id, 'download', 'ProjectFile', file.id);
    res.set({ 'Content-Type': file.mime, 'Content-Disposition': `attachment; filename="${encodeURIComponent(file.name)}"` });
    return new StreamableFile(createReadStream(path.join(this.filesDir, file.storageKey)));
  }
}

@Controller()
export class ProjectsController {
  constructor(private svc: ProjectsService, private jwt: JwtService, private access: AccessService) {}

  @Get('projects')
  list(@CurrentActor() actor: Actor) {
    return this.svc.list(actor);
  }

  @Post('projects')
  create(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Body() dto: ProjectDto) {
    return this.svc.create(actor, ability, dto);
  }

  @Get('projects/:id')
  get(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string) {
    return this.svc.get(actor, ability, id);
  }

  @Patch('projects/:id')
  update(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string, @Body() dto: ProjectDto) {
    return this.svc.update(actor, ability, id, dto);
  }

  @Post('projects/:id/members')
  member(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string, @Body() dto: MemberDto) {
    return this.svc.setMember(actor, ability, id, dto);
  }

  @Post('projects/:id/milestones')
  milestone(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string, @Body() dto: MilestoneDto) {
    return this.svc.addMilestone(actor, ability, id, dto);
  }

  @Get('projects/:id/tasks')
  tasks(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string, @Query('mine') mine?: string) {
    return this.svc.tasks(actor, ability, id, mine === 'true');
  }

  @Post('projects/:id/tasks')
  createTask(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string, @Body() dto: TaskDto) {
    return this.svc.createTask(actor, ability, id, dto);
  }

  @Get('tasks/mine')
  myTasks(@CurrentActor() actor: Actor) {
    return this.svc.myTasks(actor);
  }

  @Patch('tasks/:id')
  updateTask(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string, @Body() dto: TaskDto) {
    return this.svc.updateTask(actor, ability, id, dto);
  }

  @Get('projects/:id/folders')
  folders(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string) {
    return this.svc.folders(actor, ability, id);
  }

  @Post('projects/:id/folders')
  createFolder(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string, @Body() dto: FolderDto) {
    return this.svc.createFolder(actor, ability, id, dto);
  }

  @Post('folders/:id/files')
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_UPLOAD } }))
  upload(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string, @UploadedFile() file?: Express.Multer.File) {
    return this.svc.upload(actor, ability, id, file);
  }

  @Get('files/:id/download')
  download(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string, @Res({ passthrough: true }) res: Response) {
    return this.svc.download(actor, ability, id, res);
  }

  /** A one-minute link the app can open in the browser or system downloader (no auth header needed). */
  @Post('files/:id/link')
  async link(@CurrentActor() actor: Actor, @CurrentAbility() ability: AppAbility, @Param('id') id: string) {
    await this.svc.checkFileAccess(actor, ability, id);
    const t = await this.jwt.signAsync({ sub: actor.id, fid: id }, { expiresIn: '60s' });
    return { path: `/api/files/${id}/dl?t=${encodeURIComponent(t)}` };
  }

  @Public() @Get('files/:id/dl')
  async signedDownload(@Param('id') id: string, @Query('t') t: string, @Res({ passthrough: true }) res: Response) {
    let payload: { sub: string; fid: string };
    try {
      payload = await this.jwt.verifyAsync(t);
    } catch {
      throw new UnauthorizedException('This download link has expired');
    }
    if (payload.fid !== id) throw new UnauthorizedException();
    const actor = await this.access.loadActor(payload.sub);
    return this.svc.download(actor, this.access.ability(actor), id, res);
  }
}

@Module({
  controllers: [ProjectsController],
  providers: [ProjectsService],
})
export class ProjectsModule {}
