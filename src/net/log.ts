// Structured one-line logger used by daemon + room. Format is human-scannable:
//
//   HH:MM:SS LEVEL room=XXXX seat=N MSG key=val key=val
//
// LOG_LEVEL env var (info|debug, default info) gates debug lines. Tests pass
// `log: () => {}` to silence output entirely.

export type LogLevel = 'debug' | 'info';

export type LogLine = {
  level: LogLevel;
  msg: string;
  ts?: number;
  room?: string;
  seat?: number;
  [key: string]: unknown;
};

export type LogFn = (line: LogLine) => void;

const RESERVED = new Set(['ts', 'level', 'msg', 'room', 'seat']);

function formatValue(v: unknown): string {
  if (typeof v === 'string') {
    return /[\s"]/.test(v) ? JSON.stringify(v) : v;
  }
  if (typeof v === 'number' || typeof v === 'boolean') return String(v);
  if (v === null || v === undefined) return String(v);
  return JSON.stringify(v);
}

export function formatLine(line: LogLine, now: () => number): string {
  const ts = line.ts ?? now();
  const time = new Date(ts).toISOString().slice(11, 19);
  const parts: string[] = [time, line.level.toUpperCase()];
  if (line.room !== undefined) parts.push('room=' + line.room);
  if (line.seat !== undefined) parts.push('seat=' + line.seat);
  parts.push(line.msg);
  const extras = Object.keys(line).filter((k) => !RESERVED.has(k)).sort();
  for (const k of extras) parts.push(k + '=' + formatValue(line[k]));
  return parts.join(' ');
}

export function makeDefaultLog(now: () => number): LogFn {
  const want = (process.env.LOG_LEVEL ?? 'info').toLowerCase();
  const wantDebug = want === 'debug';
  return (line) => {
    if (line.level === 'debug' && !wantDebug) return;
    process.stdout.write(formatLine(line, now) + '\n');
  };
}
