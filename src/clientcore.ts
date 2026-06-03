// Pure client reducer + helpers used by the network client. Extracted so it
// can be unit-tested without a socket or a terminal.

import type { State } from './engine.js';
import type { GameEvent, S2C, SeatView } from './net/protocol.js';
import { seatColor, type ViewOpts, type SeatView as RSeatView } from './render.js';

export type ClientPhase =
  | { kind: 'menu' }
  | { kind: 'joining' }
  | { kind: 'lobby'; code: string; host: number; seats: SeatView[]; mySeat: number }
  | { kind: 'playing'; code: string; state: State; seats: SeatView[]; mySeat: number; lastEvent?: GameEvent }
  | { kind: 'over'; code: string; state: State; seats: SeatView[]; mySeat: number }
  | { kind: 'turn-reminder'; seat: number; secondsLeft: number };

export type ClientState = {
  token: string | null;
  name: string;
  phase: ClientPhase;
  // Persisted across phases for the game-screen footer overlay.
  reminder: { seat: number; secondsLeft: number } | null;
  // Last error to surface in the footer.
  error: string | null;
};

export function initial(name: string, token: string | null): ClientState {
  return {
    token,
    name,
    phase: { kind: 'menu' },
    reminder: null,
    error: null,
  };
}

// Apply an incoming server message. Returns a new state and a list of side
// effects (token to persist, terminal teardown signal).
export type Side =
  | { t: 'persist-token'; token: string }
  | { t: 'teardown'; exitCode: number };

export function reduce(prev: ClientState, msg: S2C): { next: ClientState; side: Side[] } {
  const side: Side[] = [];
  switch (msg.t) {
    case 'WELCOME': {
      const next: ClientState = { ...prev, token: msg.token };
      side.push({ t: 'persist-token', token: msg.token });
      // seatHint? We'll let the dispatcher re-issue JOIN_ROOM if needed.
      return { next, side };
    }
    case 'ROOM_STATE': {
      const mySeat = findMySeat(msg.seats, prev.name, prev.token);
      if (msg.phase === 'lobby') {
        return {
          next: {
            ...prev,
            phase: { kind: 'lobby', code: msg.code, host: msg.host, seats: msg.seats, mySeat },
            error: null,
          },
          side,
        };
      }
      // ROOM_STATE during playing/over: keep prev game state; refresh seats.
      if (prev.phase.kind === 'playing') {
        return {
          next: {
            ...prev,
            phase: { ...prev.phase, seats: msg.seats, mySeat },
          },
          side,
        };
      }
      return { next: prev, side };
    }
    case 'GAME_STATE': {
      const reminderCleared = prev.reminder && msg.state.current !== prev.reminder.seat
        ? null
        : prev.reminder;
      if (msg.state.phase === 'over') {
        return {
          next: {
            ...prev,
            phase: { kind: 'over', code: codeFromPrev(prev), state: msg.state, seats: msg.seats, mySeat: msg.viewerSeat },
            reminder: null,
          },
          side,
        };
      }
      return {
        next: {
          ...prev,
          phase: {
            kind: 'playing',
            code: codeFromPrev(prev),
            state: msg.state,
            seats: msg.seats,
            mySeat: msg.viewerSeat,
            lastEvent: msg.lastEvent,
          },
          reminder: reminderCleared,
        },
        side,
      };
    }
    case 'TURN_REMINDER': {
      return {
        next: {
          ...prev,
          reminder: { seat: msg.seat, secondsLeft: msg.secondsLeft },
        },
        side,
      };
    }
    case 'ERROR': {
      return { next: { ...prev, error: msg.code + ': ' + msg.message }, side };
    }
    case 'BYE': {
      // Any BYE triggers cleanup. "replaced" and "server shutting down" exit 0;
      // other reasons also exit 0 since this is server-initiated.
      side.push({ t: 'teardown', exitCode: 0 });
      return { next: prev, side };
    }
  }
}

function codeFromPrev(prev: ClientState): string {
  if (prev.phase.kind === 'lobby' || prev.phase.kind === 'playing' || prev.phase.kind === 'over') {
    return prev.phase.code;
  }
  return '';
}

function findMySeat(seats: SeatView[], name: string, _token: string | null): number {
  // Best-effort: match by name. The server-side seat assignment is the truth;
  // GAME_STATE.viewerSeat is authoritative. For ROOM_STATE during lobby, the
  // name match is good enough since we don't have viewerSeat on the wire.
  for (const s of seats) {
    if (s.name === name) return s.seat;
  }
  return -1;
}

// ─── ViewOpts construction ──────────────────────────────────────────────────
export function viewOptsFor(
  seats: SeatView[],
  viewerSeat: number,
  opts: { footer?: string; spinIdx?: number; spinFrame?: number; spinGlint?: boolean } = {},
): ViewOpts {
  const rseats: RSeatView[] = seats.map((s) => ({
    label: s.seat === viewerSeat ? 'YOU' : s.name,
    color: seatColor(s.seat),
    kind: s.kind,
    connected: s.connected,
  }));
  return { viewerSeat, seats: rseats, ...opts };
}

// ─── lobby footer formatting ────────────────────────────────────────────────
export function lobbyFooter(state: ClientState): string {
  if (state.phase.kind !== 'lobby') return '';
  const isHost = state.phase.mySeat === state.phase.host;
  const parts: string[] = ['[R]eady'];
  if (isHost) parts.push('[A]dd AI', '[K]ick seat', '[S]tart');
  parts.push('[L]eave', '[Q]uit');
  const base = '> ' + parts.join('  ');
  return state.error ? base + '   err: ' + state.error : base;
}
