-- CreateTable
CREATE TABLE "RolePermission" (
    "role" "Role" NOT NULL,
    "permission" TEXT NOT NULL,
    "updatedBy" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RolePermission_pkey" PRIMARY KEY ("role","permission")
);

-- CreateTable
CREATE TABLE "PermissionOverride" (
    "employeeId" TEXT NOT NULL,
    "permission" TEXT NOT NULL,
    "granted" BOOLEAN NOT NULL,
    "updatedBy" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PermissionOverride_pkey" PRIMARY KEY ("employeeId","permission")
);

-- AddForeignKey
ALTER TABLE "PermissionOverride" ADD CONSTRAINT "PermissionOverride_employeeId_fkey" FOREIGN KEY ("employeeId") REFERENCES "Employee"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Default grants: exactly the access the hard-coded rules gave before this migration.
INSERT INTO "RolePermission" ("role", "permission") VALUES
    ('HR', 'employees.viewSensitive'), ('HR_ADMIN', 'employees.viewSensitive'), ('FINANCE', 'employees.viewSensitive'),
    ('HR', 'employees.manage'), ('HR_ADMIN', 'employees.manage'),
    ('HR', 'invites.send'), ('HR_ADMIN', 'invites.send'),
    ('HR', 'leave.viewAll'), ('HR_ADMIN', 'leave.viewAll'),
    ('HR', 'leave.approve'), ('HR_ADMIN', 'leave.approve'),
    ('HR', 'leave.manageTypes'), ('HR_ADMIN', 'leave.manageTypes'),
    ('HR', 'holidays.manage'), ('HR_ADMIN', 'holidays.manage'),
    ('HR', 'policies.manage'), ('HR_ADMIN', 'policies.manage'),
    ('HR', 'meals.viewReport'), ('HR_ADMIN', 'meals.viewReport'), ('FINANCE', 'meals.viewReport'),
    ('HR_ADMIN', 'projects.manageAll');
