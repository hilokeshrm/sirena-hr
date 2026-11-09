-- Temporary passwords set by HR must be changed at sign-in
ALTER TABLE "Employee" ADD COLUMN "mustChangePassword" BOOLEAN NOT NULL DEFAULT false;
