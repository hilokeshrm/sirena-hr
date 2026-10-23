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
