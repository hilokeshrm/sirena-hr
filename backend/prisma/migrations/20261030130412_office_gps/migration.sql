-- AlterEnum
ALTER TYPE "CheckMethod" ADD VALUE 'GPS';

-- AlterTable
ALTER TABLE "Attendance" ADD COLUMN     "accuracyM" DOUBLE PRECISION,
ADD COLUMN     "latitude" DOUBLE PRECISION,
ADD COLUMN     "longitude" DOUBLE PRECISION;

-- AlterTable
ALTER TABLE "OfficeNetwork" ADD COLUMN     "latitude" DOUBLE PRECISION,
ADD COLUMN     "longitude" DOUBLE PRECISION,
ADD COLUMN     "radiusM" INTEGER NOT NULL DEFAULT 150;
