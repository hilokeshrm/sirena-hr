import { Global, Injectable, Module } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class AuditService {
  constructor(private prisma: PrismaService) {}

  log(actorId: string | null, action: string, entity: string, entityId?: string, meta?: Prisma.InputJsonValue) {
    return this.prisma.auditLog.create({ data: { actorId, action, entity, entityId, meta } });
  }
}

/** Never written to the log, whatever changed. */
const SECRET_FIELDS = new Set(['passwordHash', 'token', 'tokensValidFrom']);

/**
 * What actually changed between two versions of a record, as `{ field: { from, to } }`.
 * Fields the caller didn't send, and values that are the same, are left out, so the log
 * shows the real edit rather than the whole record.
 */
export function changedFields(before: Record<string, unknown>, after: Record<string, unknown>): Prisma.InputJsonObject | undefined {
  const out: Record<string, Prisma.InputJsonValue> = {};
  for (const [key, to] of Object.entries(after)) {
    if (to === undefined || SECRET_FIELDS.has(key)) continue;
    const from = before[key];
    if (plain(from) === plain(to)) continue;
    out[key] = { from: show(from), to: show(to) };
  }
  return Object.keys(out).length ? out : undefined;
}

/** Dates and arrays compare badly by value; compare their text instead. */
const plain = (v: unknown) => (v instanceof Date ? v.toISOString() : JSON.stringify(v ?? null));
const show = (v: unknown): Prisma.InputJsonValue => (v instanceof Date ? v.toISOString().slice(0, 10) : (JSON.parse(JSON.stringify(v ?? null)) as Prisma.InputJsonValue));

@Injectable()
export class NotifyService {
  constructor(private prisma: PrismaService) {}

  send(employeeIds: string | string[], title: string, link?: string) {
    const ids = Array.isArray(employeeIds) ? employeeIds : [employeeIds];
    if (!ids.length) return Promise.resolve({ count: 0 });
    return this.prisma.notification.createMany({ data: ids.map((employeeId) => ({ employeeId, title, link })) });
  }
}

@Global()
@Module({
  providers: [AuditService, NotifyService],
  exports: [AuditService, NotifyService],
})
export class CommonModule {}
