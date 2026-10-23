// Date helpers. All business dates are calendar days in India Standard Time
// and travel through the API as 'YYYY-MM-DD' strings.

export const TZ = 'Asia/Kolkata';

/** Today's date in IST as 'YYYY-MM-DD'. */
export function todayIST(now = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
}

/** Current IST time as minutes since midnight. */
export function minutesNowIST(now = new Date()): number {
  const parts = new Intl.DateTimeFormat('en-GB', { timeZone: TZ, hour: '2-digit', minute: '2-digit', hour12: false }).formatToParts(now);
  const h = Number(parts.find((p) => p.type === 'hour')?.value ?? 0);
  const m = Number(parts.find((p) => p.type === 'minute')?.value ?? 0);
  return (h % 24) * 60 + m;
}

/** 'HH:MM' → minutes since midnight. */
export function hhmmToMinutes(v: string): number {
  const [h, m] = v.split(':').map(Number);
  return h * 60 + (m || 0);
}

/** 'YYYY-MM-DD' → Date at UTC midnight (how Prisma stores @db.Date). */
export function toDbDate(day: string): Date {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) throw new Error(`Invalid date: ${day}`);
  return new Date(`${day}T00:00:00.000Z`);
}

/** Date (UTC midnight) → 'YYYY-MM-DD'. */
export function fromDbDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

export function addDays(day: string, n: number): string {
  const d = toDbDate(day);
  d.setUTCDate(d.getUTCDate() + n);
  return fromDbDate(d);
}

/** Inclusive list of days between two 'YYYY-MM-DD' strings. */
export function eachDay(from: string, to: string): string[] {
  const out: string[] = [];
  for (let d = from; d <= to; d = addDays(d, 1)) out.push(d);
  return out;
}

/** 'YYYY-MM' → first day, last day and the first day of the next month. */
export function monthBounds(month: string): { first: string; last: string; nextFirst: string } {
  const [y, m] = month.split('-').map(Number);
  return {
    first: `${month}-01`,
    last: fromDbDate(new Date(Date.UTC(y, m, 0))),
    nextFirst: fromDbDate(new Date(Date.UTC(y, m, 1))),
  };
}

export function isWeekend(day: string): boolean {
  const dow = toDbDate(day).getUTCDay();
  return dow === 0 || dow === 6;
}

/** Keys of a DTO that were actually sent (validated DTO classes carry undefined fields). */
export function sentKeys(dto: object): string[] {
  return Object.entries(dto).filter(([, v]) => v !== undefined).map(([k]) => k);
}
