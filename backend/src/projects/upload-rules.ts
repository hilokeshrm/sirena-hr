import path from 'node:path';

// Files a browser or Windows would run or render as a page. Project files are documents, drawings
// and archives; these are refused so a shared folder can't be used to spread malware or scripts.
const BLOCKED_EXTENSIONS = new Set([
  'exe', 'msi', 'msp', 'bat', 'cmd', 'com', 'scr', 'pif', 'cpl', 'dll', 'sys', 'ps1', 'psm1', 'vbs', 'vbe', 'js', 'jse', 'mjs',
  'wsf', 'wsh', 'hta', 'jar', 'lnk', 'reg', 'sh', 'apk', 'html', 'htm', 'xhtml', 'shtml', 'svg', 'php', 'jsp', 'asp', 'aspx',
]);

/** Why this file name can't be uploaded, or null. */
export function uploadProblem(name: string): string | null {
  const base = path.basename(name).trim();
  if (!base || base.startsWith('.')) return 'This file needs a name';
  const ext = base.includes('.') ? base.toLowerCase().split('.').pop()!.trim() : '';
  return BLOCKED_EXTENSIONS.has(ext) ? `.${ext} files can't be uploaded. Zip it first if you really need to share it.` : null;
}
