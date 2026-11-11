import { sessionCutoff, tokenStillValid } from '../access/access.service';
import { corsOrigins, API_SECURITY_HEADERS } from '../common/security';
import { uploadProblem } from '../projects/upload-rules';
import { checkedJwtSecret, inviteProblem } from './auth-rules';
import { LOCK_MS, LoginLimiter, MAX_ACCOUNT_FAILS, MAX_IP_FAILS } from './login-limiter';
import { passwordProblem } from './password-policy';

describe('passwordProblem', () => {
  it('accepts a long, uncommon password', () => {
    expect(passwordProblem('tulip-Harbour-42', { email: 'asha@sirenatech.com', fullName: 'Asha Rao' })).toBeNull();
  });

  it.each([
    ['short', 'Ab1!xyz'],
    ['the shared default', 'Sirena@123'],
    ['a variant of the default', 'SIRENA#2026!'],
    ['a common word', 'Password@123'],
    ['digits only', '12345678901'],
    ['one repeated character', 'aaaaaaaaaaaa'],
  ])('refuses %s', (_, pw) => {
    expect(passwordProblem(pw)).not.toBeNull();
  });

  it('refuses the email name and the person’s name', () => {
    expect(passwordProblem('asha.rao-2026', { email: 'asha.rao@sirenatech.com' })).toMatch(/email/);
    expect(passwordProblem('kumaresan#7781', { fullName: 'Kumaresan P' })).toMatch(/name/);
  });

  it('refuses more than bcrypt can use', () => {
    expect(passwordProblem('x'.repeat(40) + 'yz'.repeat(20))).toMatch(/at most/);
  });
});

describe('LoginLimiter', () => {
  it('locks an account after repeated failures and unlocks after 15 minutes', () => {
    let now = 1_000_000;
    const l = new LoginLimiter(() => now);
    for (let i = 1; i < MAX_ACCOUNT_FAILS; i++) expect(l.fail('a@x', `10.0.0.${i}`)).toBe(false);
    expect(l.isLocked('a@x', '10.9.9.9')).toBe(false);
    expect(l.fail('a@x', '10.0.0.99')).toBe(true);
    expect(l.isLocked('a@x', '10.9.9.9')).toBe(true);
    expect(l.isLocked('b@x', '10.9.9.9')).toBe(false);
    now += LOCK_MS + 1;
    expect(l.isLocked('a@x', '10.9.9.9')).toBe(false);
    // A fresh window: one more failure doesn't relock at once.
    l.fail('a@x', '10.9.9.9');
    expect(l.isLocked('a@x', '10.9.9.9')).toBe(false);
  });

  it('locks an address that tries many accounts', () => {
    const l = new LoginLimiter(() => 5);
    for (let i = 0; i < MAX_IP_FAILS; i++) l.fail(`user${i}@x`, '203.0.113.9');
    expect(l.isLocked('someone-new@x', '203.0.113.9')).toBe(true);
    expect(l.isLocked('someone-new@x', '203.0.113.10')).toBe(false);
  });

  it('clears the account count on success', () => {
    const l = new LoginLimiter(() => 5);
    for (let i = 0; i < MAX_ACCOUNT_FAILS - 1; i++) l.fail('a@x', 'ip');
    l.succeed('a@x');
    l.fail('a@x', 'ip');
    expect(l.isLocked('a@x', 'other')).toBe(false);
  });
});

describe('session revocation', () => {
  it('keeps tokens when nothing was revoked', () => {
    expect(tokenStillValid(100, null)).toBe(true);
  });

  it('refuses tokens issued before the cutoff, accepts ones issued at or after it', () => {
    const cutoff = sessionCutoff(1_700_000_000_500);
    expect(cutoff.getTime()).toBe(1_700_000_000_000);
    expect(tokenStillValid(1_699_999_999, cutoff)).toBe(false);
    expect(tokenStillValid(1_700_000_000, cutoff)).toBe(true);
    expect(tokenStillValid(undefined, cutoff)).toBe(false);
  });
});

describe('inviteProblem', () => {
  const hr = { role: 'HR' as const, locationId: 'blr' };
  const fresh = { passwordHash: null, role: 'EMPLOYEE' as const, status: 'ONBOARDING', locationId: 'blr' };

  it('lets HR invite a new joiner at their location', () => {
    expect(inviteProblem(hr, fresh)).toBeNull();
  });

  it('stops HR from resetting an existing account (account takeover)', () => {
    expect(inviteProblem(hr, { ...fresh, passwordHash: 'x' })).toMatch(/already has an account/);
    expect(inviteProblem(hr, { ...fresh, role: 'SUPER_ADMIN' })).toMatch(/super admin/);
  });

  it('keeps location-scoped HR to their own location', () => {
    expect(inviteProblem(hr, { ...fresh, locationId: 'chn' })).toMatch(/your location/);
    expect(inviteProblem({ role: 'HR_ADMIN', locationId: 'blr' }, { ...fresh, locationId: 'chn' })).toBeNull();
  });

  it('lets a super admin re-invite anyone still working here', () => {
    expect(inviteProblem({ role: 'SUPER_ADMIN', locationId: null }, { ...fresh, passwordHash: 'x', role: 'HR' })).toBeNull();
    expect(inviteProblem({ role: 'SUPER_ADMIN', locationId: null }, { ...fresh, status: 'EXITED' })).toMatch(/left/);
  });
});

describe('checkedJwtSecret', () => {
  it('refuses missing, short and example secrets', () => {
    expect(() => checkedJwtSecret(undefined)).toThrow();
    expect(() => checkedJwtSecret('short')).toThrow();
    expect(() => checkedJwtSecret('change-me-to-a-long-random-string-please-ok')).toThrow();
    expect(checkedJwtSecret('k'.repeat(48))).toBe('k'.repeat(48));
  });
});

describe('uploadProblem', () => {
  it.each(['plan.pdf', 'drawing.dwg', 'site.html.zip', 'Report v2.xlsx', 'photo.JPG'])('accepts %s', (n) => {
    expect(uploadProblem(n)).toBeNull();
  });
  it.each(['setup.exe', 'invoice.pdf.exe', 'run.BAT', 'page.html', 'logo.svg', 'tool.ps1', '.env'])('refuses %s', (n) => {
    expect(uploadProblem(n)).not.toBeNull();
  });
});

describe('API headers and CORS', () => {
  it('sets the headers helmet would for a JSON API', () => {
    expect(API_SECURITY_HEADERS['X-Content-Type-Options']).toBe('nosniff');
    expect(API_SECURITY_HEADERS['Content-Security-Policy']).toContain("frame-ancestors 'none'");
    expect(API_SECURITY_HEADERS['Cache-Control']).toBe('no-store');
  });

  it('allows only listed origins, and none by default in production', () => {
    expect(corsOrigins('https://106.51.67.75:8888', true)).toEqual(['https://106.51.67.75:8888']);
    expect(corsOrigins('', true)).toBe(false);
    expect(corsOrigins(undefined, false)).toBe(true);
  });
});
