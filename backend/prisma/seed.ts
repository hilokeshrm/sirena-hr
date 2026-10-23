// Development seed data. Run with: npm run db:seed
// All seeded accounts use the password in SEED_PASSWORD (default below) — for local testing only.
import { PrismaClient, Role } from '@prisma/client';
import * as bcrypt from 'bcryptjs';

const prisma = new PrismaClient();
const SEED_PASSWORD = process.env.SEED_PASSWORD ?? 'Sirena@Dev2026';
const d = (s: string) => new Date(`${s}T00:00:00.000Z`);

async function main() {
  const hash = await bcrypt.hash(SEED_PASSWORD, 10);

  const [eng, design, sales, ops, hr, finance] = await Promise.all(
    ['Engineering', 'Design', 'Sales', 'Operations', 'HR', 'Finance'].map((name) => prisma.department.upsert({ where: { name }, create: { name }, update: {} })),
  );
  const [chennai, blr] = await Promise.all(
    ['Chennai', 'Bengaluru', 'Remote'].map((name) => prisma.location.upsert({ where: { name }, create: { name }, update: {} })),
  );

  if (!(await prisma.officeNetwork.count())) {
    await prisma.officeNetwork.createMany({
      data: [
        // Replace with your real access-point BSSIDs and office public IP.
        { locationId: chennai.id, ssid: 'Sirena-Office', bssids: ['aa:bb:cc:dd:ee:01', 'aa:bb:cc:dd:ee:02'], publicIp: null },
        { locationId: blr.id, ssid: 'Sirena-BLR', bssids: ['aa:bb:cc:dd:ee:11'], publicIp: null },
      ],
    });
  }

  const leaveTypes = [
    { code: 'CL', name: 'Casual leave', yearlyQuota: 12, accrual: 'MONTHLY', minNoticeDays: 1, maxConsecutiveDays: 3, hrApproval: 'ABOVE_DAYS', hrApprovalAboveDays: 3 },
    { code: 'SL', name: 'Sick leave', yearlyQuota: 12, accrual: 'UPFRONT', minNoticeDays: 0, maxConsecutiveDays: 10, hrApproval: 'ABOVE_DAYS', hrApprovalAboveDays: 2 },
    { code: 'EL', name: 'Earned leave', yearlyQuota: 18, accrual: 'MONTHLY', carryForwardMax: 30, minNoticeDays: 7, maxConsecutiveDays: 15, sandwich: true, hrApproval: 'ALWAYS' },
    { code: 'CO', name: 'Comp-off', yearlyQuota: null, accrual: 'NONE', minNoticeDays: 1, maxConsecutiveDays: 2, hrApproval: 'NEVER' },
    { code: 'ML', name: 'Maternity leave', yearlyQuota: 182, accrual: 'UPFRONT', minNoticeDays: 30, allowHalfDay: false, sandwich: true, hrApproval: 'ALWAYS' },
    { code: 'PL', name: 'Paternity leave', yearlyQuota: 5, accrual: 'UPFRONT', minNoticeDays: 7, hrApproval: 'ALWAYS' },
    { code: 'LOP', name: 'Loss of pay', yearlyQuota: null, accrual: 'NONE', allowNegative: true, minNoticeDays: 1, sandwich: true, hrApproval: 'ALWAYS' },
  ] as const;
  for (const t of leaveTypes) await prisma.leaveType.upsert({ where: { code: t.code }, create: { ...t }, update: {} });
  const types = await prisma.leaveType.findMany();
  const T = Object.fromEntries(types.map((t) => [t.code, t]));

  const holidays = [
    ['2026-01-01', 'New Year’s Day', false, null], ['2026-01-15', 'Pongal', false, chennai.id], ['2026-01-26', 'Republic Day', false, null],
    ['2026-03-04', 'Holi', true, null], ['2026-03-19', 'Ugadi', false, blr.id], ['2026-04-03', 'Good Friday', true, null],
    ['2026-05-01', 'May Day', false, null], ['2026-09-14', 'Ganesh Chaturthi', true, null], ['2026-10-02', 'Gandhi Jayanti', false, null],
    ['2026-10-20', 'Dussehra', false, null], ['2026-11-09', 'Diwali (observed)', false, null], ['2026-12-25', 'Christmas', true, null],
  ] as const;
  for (const [date, name, optional, locationId] of holidays) {
    const exists = await prisma.holiday.findFirst({ where: { date: d(date), locationId } });
    if (!exists) await prisma.holiday.create({ data: { date: d(date), name, optional, locationId } });
  }

  type P = { code: string; email: string; fullName: string; role?: Role; dept: string; designation: string; loc: string; manager?: string; joined: string; food?: 'VEG' | 'NON_VEG' };
  const people: P[] = [
    { code: 'SIR-0001', email: 'ravi.shankar@sirena.in', fullName: 'Ravi Shankar', role: 'SUPER_ADMIN', dept: ops.id, designation: 'Director', loc: chennai.id, joined: '2019-04-01' },
    { code: 'SIR-0012', email: 'meena.k@sirena.in', fullName: 'Meena Krishnan', role: 'HR_ADMIN', dept: hr.id, designation: 'HR Manager', loc: chennai.id, manager: 'SIR-0001', joined: '2020-04-15', food: 'VEG' },
    { code: 'SIR-0031', email: 'arjun.mehta@sirena.in', fullName: 'Arjun Mehta', dept: eng.id, designation: 'Engineering Manager', loc: chennai.id, manager: 'SIR-0001', joined: '2021-08-02', food: 'NON_VEG' },
    { code: 'SIR-0098', email: 'karthik.s@sirena.in', fullName: 'Karthik S', dept: eng.id, designation: 'Senior Engineer', loc: chennai.id, manager: 'SIR-0031', joined: '2022-01-03', food: 'NON_VEG' },
    { code: 'SIR-0120', email: 'divya.nair@sirena.in', fullName: 'Divya Nair', dept: eng.id, designation: 'QA Engineer', loc: blr.id, manager: 'SIR-0031', joined: '2022-09-11', food: 'VEG' },
    { code: 'SIR-0142', email: 'priya.raman@sirena.in', fullName: 'Priya Raman', dept: eng.id, designation: 'Software Engineer', loc: chennai.id, manager: 'SIR-0031', joined: '2023-06-14', food: 'VEG' },
    { code: 'SIR-0105', email: 'rahul.verma@sirena.in', fullName: 'Rahul Verma', dept: design.id, designation: 'Product Designer', loc: chennai.id, manager: 'SIR-0031', joined: '2022-03-20', food: 'VEG' },
    { code: 'SIR-0164', email: 'kavya.reddy@sirena.in', fullName: 'Kavya Reddy', role: 'FINANCE', dept: finance.id, designation: 'Payroll Specialist', loc: chennai.id, manager: 'SIR-0001', joined: '2024-02-05', food: 'VEG' },
    { code: 'SIR-0171', email: 'nikhil.joshi@sirena.in', fullName: 'Nikhil Joshi', dept: sales.id, designation: 'Account Executive', loc: blr.id, manager: 'SIR-0001', joined: '2026-10-05', food: 'NON_VEG' },
  ];
  const ids: Record<string, string> = {};
  for (const p of people) {
    const e = await prisma.employee.upsert({
      where: { code: p.code },
      create: {
        code: p.code, email: p.email, fullName: p.fullName, role: p.role ?? 'EMPLOYEE', departmentId: p.dept, designation: p.designation,
        locationId: p.loc, joinedOn: d(p.joined), foodPref: p.food, passwordHash: hash, status: 'ACTIVE',
      },
      update: {},
    });
    ids[p.code] = e.id;
  }
  for (const p of people) if (p.manager) await prisma.employee.update({ where: { id: ids[p.code] }, data: { managerId: ids[p.manager] } });

  // Opening balances for 2026: up-front types in full, monthly types for Jan–Sep.
  if (!(await prisma.leaveLedger.count())) {
    for (const id of Object.values(ids)) {
      for (const t of types) {
        if (t.accrual === 'UPFRONT' && t.yearlyQuota) {
          await prisma.leaveLedger.create({ data: { employeeId: id, leaveTypeId: t.id, year: 2026, delta: Number(t.yearlyQuota), reason: 'OPENING', refId: `open:2026:${t.id}:upfront` } });
        }
        if (t.accrual === 'MONTHLY' && t.yearlyQuota) {
          for (let m = 1; m <= 9; m++) {
            await prisma.leaveLedger.create({ data: { employeeId: id, leaveTypeId: t.id, year: 2026, delta: Number(t.yearlyQuota) / 12, reason: 'ACCRUAL', refId: `accrual:2026-${m}:${t.id}` } });
          }
        }
      }
    }
    await prisma.leaveLedger.create({ data: { employeeId: ids['SIR-0142'], leaveTypeId: T.CO.id, year: 2026, delta: 1, reason: 'ADJUSTMENT', note: 'Weekend release support' } });
  }

  if (!(await prisma.project.count())) {
    const atlas = await prisma.project.create({
      data: {
        code: 'ATL-26', name: 'Atlas Mobile Revamp', client: 'Brightline Logistics', status: 'ON_TRACK', startDate: d('2026-06-01'), endDate: d('2027-03-31'), leadId: ids['SIR-0031'],
        members: {
          create: [
            { employeeId: ids['SIR-0031'], role: 'LEAD', allocation: 50 },
            { employeeId: ids['SIR-0098'], role: 'TECH_LEAD', allocation: 80 },
            { employeeId: ids['SIR-0142'], role: 'MEMBER', allocation: 60 },
            { employeeId: ids['SIR-0120'], role: 'MEMBER', allocation: 100 },
          ],
        },
        milestones: { create: [{ name: 'Design sign-off', dueDate: d('2026-10-01'), done: true }, { name: 'Driver app beta', dueDate: d('2026-10-30') }, { name: 'Store release', dueDate: d('2027-01-15') }] },
        folders: { create: [{ name: 'Designs' }, { name: 'Specs & notes' }, { name: 'Client docs', sensitivity: 'RESTRICTED' }] },
        tasks: {
          create: [
            { title: 'Offline sync for delivery list', status: 'IN_PROGRESS', priority: 'HIGH', assigneeId: ids['SIR-0142'], dueDate: d('2026-10-23') },
            { title: 'Fix crash on proof-of-delivery photo', status: 'IN_REVIEW', priority: 'URGENT', assigneeId: ids['SIR-0142'], dueDate: d('2026-10-21') },
            { title: 'Driver login with OTP', status: 'DONE', priority: 'MEDIUM', assigneeId: ids['SIR-0098'] },
            { title: 'Route optimisation API', status: 'IN_PROGRESS', priority: 'HIGH', assigneeId: ids['SIR-0098'], dueDate: d('2026-10-28') },
            { title: 'Accessibility pass on driver app', status: 'TODO', priority: 'MEDIUM', assigneeId: ids['SIR-0120'] },
          ],
        },
      },
    });
    await prisma.project.create({
      data: {
        code: 'HRS-26', name: 'Internal HR Suite', client: 'Internal', status: 'AT_RISK', startDate: d('2026-08-01'), endDate: d('2027-01-15'), leadId: ids['SIR-0142'],
        members: { create: [{ employeeId: ids['SIR-0142'], role: 'LEAD', allocation: 40 }, { employeeId: ids['SIR-0105'], role: 'MEMBER', allocation: 60 }] },
        folders: { create: [{ name: 'Designs' }, { name: 'Plans' }] },
        tasks: { create: [{ title: 'Wi-Fi check-in endpoint', status: 'TODO', priority: 'HIGH', assigneeId: ids['SIR-0142'], dueDate: d('2026-10-30') }] },
      },
    });
    void atlas;
  }

  if (!(await prisma.policy.count())) {
    await prisma.policy.create({
      data: {
        title: 'Work From Home Policy', category: 'Work', requireAck: true,
        versions: {
          create: {
            version: 1,
            body: '## Who can work from home\nConfirmed employees, up to three days a week, with their manager’s agreement.\n\n## Being reachable\nStay on chat and calls during core hours, 11:00–16:00 IST.\n\n## Security\nCompany laptop only, always on VPN.',
            changeSummary: 'WFH goes from 2 to 3 days a week.',
            publishedAt: new Date(), ackDueAt: new Date(Date.now() + 14 * 864e5),
          },
        },
      },
    });
    await prisma.policy.create({
      data: {
        title: 'Leave Policy 2026', category: 'Leave', requireAck: true,
        versions: { create: { version: 1, body: 'Casual 12, sick 12 and earned 18 days a year. Earned leave carries forward up to 30 days.', publishedAt: new Date('2026-01-02') } },
      },
    });
  }

  console.log(`Seeded. Sign in with any seeded email (e.g. priya.raman@sirena.in, meena.k@sirena.in) and the SEED_PASSWORD.`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
