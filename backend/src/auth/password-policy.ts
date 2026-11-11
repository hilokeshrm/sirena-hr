/** Rules every new password must meet (sign-up, change password). */
export const PASSWORD_MIN = 10;
// bcrypt only uses the first 72 bytes; longer input is refused rather than silently cut.
export const PASSWORD_MAX = 72;

// Words that make a password easy to guess here: the company name, the shared temporary
// password, and the most common choices. Compared after dropping digits and symbols.
const WEAK_WORDS = new Set([
  'sirena', 'sirenatech', 'sirenahr', 'password', 'passw', 'welcome', 'qwerty', 'qwertyuiop', 'asdf', 'asdfgh', 'admin',
  'letmein', 'changeme', 'iloveyou', 'abc', 'abcd', 'abcdef', 'india', 'monkey', 'dragon', 'login', 'test', 'temp',
]);

/** Why `password` is not acceptable, or null if it is. */
export function passwordProblem(password: string, person: { email?: string | null; fullName?: string | null } = {}): string | null {
  if (password.length < PASSWORD_MIN) return `Use at least ${PASSWORD_MIN} characters`;
  if (Buffer.byteLength(password, 'utf8') > PASSWORD_MAX) return `Use at most ${PASSWORD_MAX} characters`;
  const lower = password.toLowerCase();
  const letters = lower.replace(/[^a-z]/g, '');
  if (!letters.length || WEAK_WORDS.has(letters)) return 'That password is too easy to guess. Avoid the company name and common words.';
  if (/^\d+$/.test(password)) return 'Use letters as well as numbers';
  if (new Set(lower).size < 4) return 'Use more different characters';
  const local = person.email?.split('@')[0]?.toLowerCase().replace(/[^a-z0-9]/g, '');
  if (local && local.length >= 3 && lower.replace(/[^a-z0-9]/g, '').includes(local)) return 'Don’t use your email address in your password';
  for (const part of (person.fullName ?? '').toLowerCase().split(/\s+/)) {
    if (part.length >= 4 && lower.includes(part)) return 'Don’t use your name in your password';
  }
  return null;
}
