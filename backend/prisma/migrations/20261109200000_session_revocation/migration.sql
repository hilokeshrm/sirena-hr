-- Sign-in tokens issued before this moment are refused.
ALTER TABLE "Employee" ADD COLUMN "tokensValidFrom" TIMESTAMP(3);
