// Creates the first super admin in an empty database (used by ops/windows/setup.ps1).
// Usage: ADMIN_EMAIL=... ADMIN_NAME=... ADMIN_PASSWORD=... [ADMIN_CODE=SIR-0001] node scripts/create-admin.mjs
import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';

if (!process.env.DATABASE_URL) process.loadEnvFile?.('.env');
const { ADMIN_EMAIL, ADMIN_NAME, ADMIN_PASSWORD, ADMIN_CODE = 'SIR-0001' } = process.env;
if (!ADMIN_EMAIL || !ADMIN_NAME || !ADMIN_PASSWORD) {
  console.error('Set ADMIN_EMAIL, ADMIN_NAME and ADMIN_PASSWORD.');
  process.exit(1);
}

const prisma = new PrismaClient();
try {
  const email = ADMIN_EMAIL.trim().toLowerCase();
  if (await prisma.employee.findUnique({ where: { email } })) {
    console.log(`${email} already exists; nothing changed.`);
  } else {
    await prisma.employee.create({
      data: {
        code: ADMIN_CODE, email, fullName: ADMIN_NAME.trim(), role: 'SUPER_ADMIN', status: 'ACTIVE',
        passwordHash: await bcrypt.hash(ADMIN_PASSWORD, 12),
      },
    });
    console.log(`Created super admin ${email}.`);
  }
} finally {
  await prisma.$disconnect();
}
