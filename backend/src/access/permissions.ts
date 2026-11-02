import { Role } from '@prisma/client';

/**
 * Permissions the super admin can switch on or off per role (and per person).
 * What each one allows is defined in `defineAbilityFor`; which roles hold it lives in the
 * RolePermission table. `defaults` must match the seed rows in the migration that created it.
 */
export const PERMISSIONS = [
  {
    key: 'employees.viewSensitive', group: 'People', label: 'View sensitive employee data',
    description: 'Personal, contact and emergency details. HR sees their own location only.',
    whenOff: 'Sees directory details only, plus their own full profile.',
    whenOn: 'Sees personal, contact and emergency details of everyone.',
    whenOnLocal: 'Sees personal, contact and emergency details of people at their location.',
    defaults: ['HR', 'HR_ADMIN', 'FINANCE'],
  },
  {
    key: 'employees.manage', group: 'People', label: 'Manage employees',
    description: 'Add employees and edit their records. HR edits their own location only.',
    whenOff: 'Can edit only their own contact details.',
    whenOn: 'Can add employees and edit anyone’s record.',
    whenOnLocal: 'Can add employees and edit records of people at their location.',
    defaults: ['HR', 'HR_ADMIN'],
  },
  {
    key: 'invites.send', group: 'People', label: 'Send invites',
    description: 'Send sign-up invites to new employees.',
    whenOff: 'Can’t send sign-up invites.',
    whenOn: 'Can send sign-up invites to new employees.',
    defaults: ['HR', 'HR_ADMIN'],
  },
  {
    key: 'leave.viewAll', group: 'Leave & attendance', label: 'View everyone’s leave & attendance',
    description: 'Not just their own team. HR sees their own location only.',
    whenOff: 'Sees their own leave and attendance, and their team’s if they manage people.',
    whenOn: 'Sees everyone’s leave and attendance.',
    whenOnLocal: 'Sees leave and attendance of everyone at their location.',
    defaults: ['HR', 'HR_ADMIN'],
  },
  {
    key: 'leave.approve', group: 'Leave & attendance', label: 'Approve leave (HR step)',
    description: 'Approve or reject requests waiting for HR. Nobody can approve their own leave.',
    whenOff: 'Approves leave only as a manager, for their own reports.',
    whenOn: 'Gives HR approval on anyone’s leave (never their own).',
    whenOnLocal: 'Gives HR approval on leave of people at their location (never their own).',
    defaults: ['HR', 'HR_ADMIN'],
  },
  {
    key: 'leave.manageTypes', group: 'Leave & attendance', label: 'Manage leave types & balances',
    description: 'Leave rules, balance adjustments, monthly accrual and year opening.',
    whenOff: 'Sees leave types and their own balances only.',
    whenOn: 'Changes leave rules, adjusts balances and runs accrual.',
    defaults: ['HR', 'HR_ADMIN'],
  },
  {
    key: 'holidays.manage', group: 'Leave & attendance', label: 'Manage holidays',
    description: 'Add and remove holidays.',
    whenOff: 'Sees the holiday list only.',
    whenOn: 'Adds and removes holidays.',
    defaults: ['HR', 'HR_ADMIN'],
  },
  {
    key: 'offices.manage', group: 'Leave & attendance', label: 'Manage office networks',
    description: 'Office Wi-Fi, IP and location used for check-in.',
    whenOff: 'Can’t change office check-in networks.',
    whenOn: 'Changes the office Wi-Fi, IP and location used for check-in.',
    defaults: [],
  },
  {
    key: 'policies.manage', group: 'Company', label: 'Manage policies',
    description: 'Write, publish and track acknowledgement of policies.',
    whenOff: 'Reads and acknowledges policies only.',
    whenOn: 'Writes, publishes and tracks policies.',
    defaults: ['HR', 'HR_ADMIN'],
  },
  {
    key: 'meals.viewReport', group: 'Company', label: 'Meal reports & menus',
    description: 'Lunch head-counts and setting the daily menu.',
    whenOff: 'Books their own lunch only.',
    whenOn: 'Sees lunch head-counts and sets the daily menu.',
    defaults: ['HR', 'HR_ADMIN', 'FINANCE'],
  },
  {
    key: 'projects.manageAll', group: 'Company', label: 'Manage all projects',
    description: 'Create projects and open or edit any project, including restricted folders.',
    whenOff: 'Sees only projects they are on; leads edit their own projects.',
    whenOn: 'Creates projects and opens or edits any project, including restricted folders.',
    defaults: ['HR_ADMIN'],
  },
  {
    key: 'audit.view', group: 'Company', label: 'View audit log',
    description: 'Who changed what, and when.',
    whenOff: 'Can’t see the audit log.',
    whenOn: 'Sees who changed what, and when.',
    defaults: [],
  },
] as const satisfies readonly {
  key: string; group: string; label: string; description: string;
  /** Plain-English effect for one person, without / with the permission (and for location-scoped roles). */
  whenOff: string; whenOn: string; whenOnLocal?: string;
  defaults: readonly Role[];
}[];

export type PermissionKey = (typeof PERMISSIONS)[number]['key'];

export const PERMISSION_KEYS: PermissionKey[] = PERMISSIONS.map((p) => p.key);

/** Roles shown in the access matrix. SUPER_ADMIN always has everything and is not editable. */
export const EDITABLE_ROLES: Role[] = ['EMPLOYEE', 'HR', 'HR_ADMIN', 'FINANCE'];

/** Roles whose people-related permissions only reach their own location. */
export const LOCATION_SCOPED_ROLES: Role[] = ['EMPLOYEE', 'HR'];

export function isPermissionKey(k: string): k is PermissionKey {
  return (PERMISSION_KEYS as string[]).includes(k);
}

export function defaultPermissionsFor(role: Role): PermissionKey[] {
  return PERMISSIONS.filter((p) => (p.defaults as readonly Role[]).includes(role)).map((p) => p.key);
}

/** What a permission means for someone in this role, in plain English. */
export function describeEffect(key: PermissionKey, role: Role, on: boolean): string {
  const p: { whenOff: string; whenOn: string; whenOnLocal?: string } = PERMISSIONS.find((x) => x.key === key)!;
  if (!on) return p.whenOff;
  return LOCATION_SCOPED_ROLES.includes(role) && p.whenOnLocal ? p.whenOnLocal : p.whenOn;
}
