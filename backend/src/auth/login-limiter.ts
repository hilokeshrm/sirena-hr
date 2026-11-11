/**
 * In-memory brute-force protection for sign-in and password checks.
 * One API process serves the company, so memory is enough; a restart clears it.
 */
export const MAX_ACCOUNT_FAILS = 5;
export const MAX_IP_FAILS = 30;
export const LOCK_MS = 15 * 60 * 1000;
// Entries are dropped once stale so the maps can't grow without bound.
const MAX_ENTRIES = 10_000;

interface Window {
  count: number;
  since: number;
}

export class LoginLimiter {
  private accounts = new Map<string, Window>();
  private ips = new Map<string, Window>();

  constructor(private now: () => number = Date.now) {}

  private live(map: Map<string, Window>, key: string): Window | undefined {
    const w = map.get(key);
    if (w && w.since <= this.now() - LOCK_MS) {
      map.delete(key);
      return undefined;
    }
    return w;
  }

  /** True when this account or address has failed too often in the last 15 minutes. */
  isLocked(account: string, ip: string) {
    return (this.live(this.accounts, account)?.count ?? 0) >= MAX_ACCOUNT_FAILS || (this.live(this.ips, ip)?.count ?? 0) >= MAX_IP_FAILS;
  }

  /** Records a failure; returns true if this failure just locked the account. */
  fail(account: string, ip: string) {
    const bump = (map: Map<string, Window>, key: string) => {
      const w = this.live(map, key);
      const next = w ? { count: w.count + 1, since: w.since } : { count: 1, since: this.now() };
      map.set(key, next);
      if (map.size > MAX_ENTRIES) this.prune(map);
      return next.count;
    };
    bump(this.ips, ip);
    return bump(this.accounts, account) === MAX_ACCOUNT_FAILS;
  }

  succeed(account: string) {
    this.accounts.delete(account);
  }

  private prune(map: Map<string, Window>) {
    const cutoff = this.now() - LOCK_MS;
    for (const [k, w] of map) if (w.since <= cutoff) map.delete(k);
    // Still full of fresh entries (an attack from many addresses): drop the oldest.
    while (map.size > MAX_ENTRIES) map.delete(map.keys().next().value!);
  }
}
