import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AccessAdminModule } from './access/access-admin.module';
import { AccessModule } from './access/access.service';
import { AttendanceModule } from './attendance/attendance.module';
import { AuthModule } from './auth/auth.module';
import { CommonModule } from './common/audit.service';
import { EmployeesModule } from './employees/employees.module';
import { HealthController } from './health.controller';
import { LeaveModule } from './leave/leave.module';
import { PoliciesModule } from './policies/policies.module';
import { AuditModule } from './audit/audit.module';
import { PrismaModule } from './prisma/prisma.service';
import { ProjectsModule } from './projects/projects.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    PrismaModule,
    CommonModule,
    AccessModule,
    AccessAdminModule,
    AuthModule,
    EmployeesModule,
    LeaveModule,
    AttendanceModule,
    ProjectsModule,
    PoliciesModule,
    AuditModule,
  ],
  controllers: [HealthController],
})
export class AppModule {}
