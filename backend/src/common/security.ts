import type { NextFunction, Request, Response } from 'express';

/**
 * Response headers for every API reply (what helmet would set for a JSON API).
 * The API never serves pages, so nothing may frame, render or cache its answers.
 */
export const API_SECURITY_HEADERS: Record<string, string> = {
  'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Referrer-Policy': 'no-referrer',
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Resource-Policy': 'same-origin',
  'X-Permitted-Cross-Domain-Policies': 'none',
  // Answers carry personal data; browsers and proxies must not keep them.
  'Cache-Control': 'no-store',
};

export function securityHeaders(_req: Request, res: Response, next: NextFunction) {
  res.set(API_SECURITY_HEADERS);
  res.removeHeader('X-Powered-By');
  next();
}

/**
 * Browser origins allowed to call the API. In production (TRUST_PROXY=true, behind Caddy) an empty
 * list means "no cross-origin callers" rather than "anyone": the website is served from the same origin
 * and the phone apps send no Origin header.
 */
export function corsOrigins(raw: string | undefined, production: boolean): string[] | boolean {
  const list = (raw ?? '').split(',').map((o) => o.trim()).filter(Boolean);
  if (list.length) return list;
  return !production;
}
