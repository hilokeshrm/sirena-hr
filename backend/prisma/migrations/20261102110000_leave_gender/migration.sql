-- Gender-specific leave types (maternity, paternity, period leave)
ALTER TABLE "LeaveType" ADD COLUMN "eligibleGender" TEXT;
