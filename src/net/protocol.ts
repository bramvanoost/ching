// Wire protocol between client and daemon. Line-delimited JSON over a unix
// domain socket. Every message: { v: 1, t: <type>, ... }.

import type { Action, State } from '../engine.js';

export const PROTOCOL_VERSION = 1;

export type SeatKind = 'human' | 'ai' | 'ai-takeover';

export type SeatView = {
  seat: number;
  name: string;
  kind: SeatKind;
  ready: boolean;
  connected: boolean;
};

export type GameEvent = 'banked' | 'stolen' | 'busted';

// ─── client → server ────────────────────────────────────────────────────────
export type C2SHello = { v: 1; t: 'HELLO'; name: string; token?: string };
export type C2SCreateRoom = { v: 1; t: 'CREATE_ROOM' };
export type C2SJoinRoom = { v: 1; t: 'JOIN_ROOM'; code: string };
export type C2SAddAiSeat = { v: 1; t: 'ADD_AI_SEAT'; discipline?: number };
export type C2SRemoveSeat = { v: 1; t: 'REMOVE_SEAT'; seat: number };
export type C2SReady = { v: 1; t: 'READY'; ready: boolean };
export type C2SStart = { v: 1; t: 'START' };
export type C2SAction = { v: 1; t: 'ACTION'; action: Action };
export type C2SLeave = { v: 1; t: 'LEAVE' };
// App-level heartbeat. Receiving any data resets the daemon's per-conn
// activity clock; PING is just an explicit "I'm still here" the client can
// send when there's nothing else to say. Daemon needn't ack — silence from
// the daemon's side is detected by the OS-level 'close' on the client.
export type C2SPing = { v: 1; t: 'PING' };

export type C2S =
  | C2SHello
  | C2SCreateRoom
  | C2SJoinRoom
  | C2SAddAiSeat
  | C2SRemoveSeat
  | C2SReady
  | C2SStart
  | C2SAction
  | C2SLeave
  | C2SPing;

// ─── server → client ────────────────────────────────────────────────────────
export type S2CWelcome = {
  v: 1;
  t: 'WELCOME';
  token: string;
  seatHint?: { code: string; seat: number };
};
export type S2CRoomState = {
  v: 1;
  t: 'ROOM_STATE';
  code: string;
  host: number;
  seats: SeatView[];
  phase: 'lobby' | 'playing' | 'over';
};
export type S2CGameState = {
  v: 1;
  t: 'GAME_STATE';
  state: State;
  viewerSeat: number;
  seats: SeatView[];
  lastEvent?: GameEvent;
};
export type S2CTurnReminder = {
  v: 1;
  t: 'TURN_REMINDER';
  seat: number;
  secondsLeft: number;
};
export type S2CError = { v: 1; t: 'ERROR'; code: string; message: string };
export type S2CBye = { v: 1; t: 'BYE'; reason: string };

export type S2C =
  | S2CWelcome
  | S2CRoomState
  | S2CGameState
  | S2CTurnReminder
  | S2CError
  | S2CBye;

// ─── encode / decode ────────────────────────────────────────────────────────
export function encode(msg: C2S | S2C): string {
  return JSON.stringify(msg) + '\n';
}

export class FrameDecoder {
  private buf = '';

  push(chunk: string | Buffer): (C2S | S2C)[] {
    this.buf += typeof chunk === 'string' ? chunk : chunk.toString('utf8');
    const out: (C2S | S2C)[] = [];
    let idx = this.buf.indexOf('\n');
    while (idx !== -1) {
      const line = this.buf.slice(0, idx);
      this.buf = this.buf.slice(idx + 1);
      if (line.length > 0) {
        out.push(decodeLine(line));
      }
      idx = this.buf.indexOf('\n');
    }
    return out;
  }
}

export class ProtocolError extends Error {
  constructor(public code: string, message: string) {
    super(code + ': ' + message);
  }
}

function decodeLine(line: string): C2S | S2C {
  let obj: unknown;
  try {
    obj = JSON.parse(line);
  } catch {
    throw new ProtocolError('BAD_JSON', 'malformed JSON: ' + line.slice(0, 80));
  }
  if (!obj || typeof obj !== 'object') {
    throw new ProtocolError('BAD_MESSAGE', 'message is not an object');
  }
  const m = obj as { v?: unknown; t?: unknown };
  if (m.v !== PROTOCOL_VERSION) {
    throw new ProtocolError('BAD_VERSION', 'unsupported protocol version: ' + String(m.v));
  }
  if (typeof m.t !== 'string') {
    throw new ProtocolError('BAD_MESSAGE', 'missing message type');
  }
  return obj as C2S | S2C;
}
