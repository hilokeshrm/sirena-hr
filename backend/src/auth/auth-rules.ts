import { Role } from '@prisma/client';
import type { Actor } from '../access/access.service';
import { LOCATION_SCOPED_ROLES } from '../access/permissions';

/**
 * Why `actor` may not send `target` an invite, or null. Accepting an invite sets the password, so
 * outside super admins it is only for people who haven't signed up yet, have no admin role, and
 * (for location-scoped roles) work at the sender's location. Otherwise HR could take over any account.
 */
export function inviteProblem(
  actor: Pick<Actor, 'role' | 'locationId'>,
  target: { passwordHash: string | null; role: Role; status: string; locationId: string | null },
): string | null {
  if (target.status === 'EXITED') return 'This person has left';
  if (actor.role === 'SUPER_ADMIN') return null;
  if (target.passwordHash) return 'This person already has an account. Ask a super admin to send a new invite.';
  if (target.role !== 'EMPLOYEE') return 'Only a super admin can invite someone with an admin role';
  if (LOCATION_SCOPED_ROLES.includes(actor.role) && target.locationId !== actor.locationId) return 'You can only invite people at your location';
  return null;
}

/** Refuses to start with a missing, short or example signing secret: anyone who knows it can sign in as anyone. */
export function checkedJwtSecret(secret: string | undefined): string {
  if (!secret || secret.length < 32 || /change-me/i.test(secret)) {
    throw new Error('JWT_SECRET must be a random string of at least 32 characters (see backend/.env.example).');
  }
  return secret;
}
