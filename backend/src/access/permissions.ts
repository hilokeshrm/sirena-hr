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
    defaults: ['HR', 'HR_ADMIN', 'FINANCE'],
  },
  {
    key: 'employees.manage', group: 'People', label: 'Manage employees',
    description: 'Add employees and edit their records. HR edits their own location only.',
    defaults: ['HR', 'HR_ADMIN'],
  },
  {
    key: 'invites.send', group: 'People', label: 'Send invites',
    description: 'Send sign-up invites to new employees.',
    defaults: ['HR', 'HR_ADMIN'],
  },
  {
    key: 'leave.viewAll', group: 'Leave & attendance', label: 'View everyone’s leave & attendance',
    description: 'Not just their own team. HR sees their own location only.',
    defaults: ['HR', 'HR_ADMIN'],
  },
  {
    key: 'leave.approve', group: 'Leave & attendance', label: 'Approve leave (HR step)',
    description: 'Approve or reject requests waiting for HR. Nobody can approve their own leave.',
    defaults: ['HR', 'HR_ADMIN'],
  },
  {
    key: 'leave.manageTypes', group: 'Leave & attendance', label: 'Manage leave types & balances',
    description: 'Leave rules, balance adjustments, monthly accrual and year opening.',
    defaults: ['HR', 'HR_ADMIN'],
  },
  {
    key: 'holidays.manage', group: 'Leave & attendance', label: 'Manage holidays',
    description: 'Add and remove holidays.',
    defaults: ['HR', 'HR_ADMIN'],
  },
  {
    key: 'offices.manage', group: 'Leave & attendance', label: 'Manage office networks',
    description: 'Office Wi-Fi, IP and location used for check-in.',
    defaults: [],
  },
  {
    key: 'policies.manage', group: 'Company', label: 'Manage policies',
    description: 'Write, publish and track acknowledgement of policies.',
    defaults: ['HR', 'HR_ADMIN'],
  },
  {
    key: 'meals.viewReport', group: 'Company', label: 'Meal reports & menus',
    description: 'Lunch head-counts and setting the daily menu.',
    defaults: ['HR', 'HR_ADMIN', 'FINANCE'],
  },
  {
    key: 'projects.manageAll', group: 'Company', label: 'Manage all projects',
    description: 'Create projects and open or edit any project, including restricted folders.',
    defaults: ['HR_ADMIN'],
  },
  {
    key: 'audit.view', group: 'Company', label: 'View audit log',
    description: 'Who changed what, and when.',
    defaults: [],
  },
] as const satisfies readonly { key: string; group: string; label: string; description: string; defaults: readonly Role[] }[];

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
