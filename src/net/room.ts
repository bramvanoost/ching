// Room: holds lobby + game state, owns RNG, drives grace timers and AI
// takeover. All I/O happens via the EventBus the daemon subscribes to.
// Synchronous methods so tests can drive with a mock clock.

import {
  initialState,
  step,
  type Action,
  type Rng,
  type State,
} from '../engine.js';
import { decide, type Difficulty } from '../ai.js';
import type { GameEvent, S2C, SeatView, SeatKind } from './protocol.js';

const MAX_SEATS = 4;
const MIN_SEATS = 2;
const GRACE_MS = 15_000;
const REMINDER_EVERY_MS = 5_000;
const AI_THINK_MS = 380;
const IDLE_REAP_MS = 30 * 60 * 1_000;
const DEFAULT_AI_DISCIPLINE = 0.6;

// Three orthogonal facts per seat:
//   - connId: socket attached (or null)
//   - aiTakingOver: AI is currently playing this seat (humans only)
//   - downSinceMs: when the human last detached (humans only)
export type SeatRecord = {
  seat: number;
  name: string;
  kindBase: 'human' | 'ai';
  ready: boolean;
  connId: string | null;
  aiTakingOver: boolean;
  downSinceMs: number | null;
  token: string;     // for humans; AI seats keep this empty
  discipline: number; // for AI seats; ignored for humans
};

export type RoomEvent =
  | { t: 'send'; connId: string; msg: S2C }
  | { t: 'bye'; connId: string; reason: string };

type Timer = { fireAtMs: number; kind: 'reminder' | 'expire' | 'ai-step' };

export type RoomDeps = {
  rng: Rng;
  now: () => number;
  bus: (e: RoomEvent) => void;
  mintToken: () => string;
};

export class Room {
  readonly code: string;
  host = 0;
  seats: SeatRecord[] = [];
  phase: 'lobby' | 'playing' | 'over' = 'lobby';
  state: State | null = null;
  private lastHumanLiveAtMs: number;
  private timers: Timer[] = [];
  reaped = false;

  constructor(code: string, private readonly deps: RoomDeps) {
    this.code = code;
    this.lastHumanLiveAtMs = deps.now();
  }

  // ─── lobby ────────────────────────────────────────────────────────────────
  joinHuman(name: string, connId: string, existingToken?: string): {
    seat: number;
    token: string;
    reclaimed: boolean;
  } {
    if (existingToken) {
      const idx = this.seats.findIndex(
        (s) => s.kindBase === 'human' && s.token === existingToken,
      );
      if (idx !== -1) {
        const prev = this.attach(idx, connId);
        return { ...prev, reclaimed: true };
      }
    }
    if (this.seats.length >= MAX_SEATS) {
      throw new RoomError('ROOM_FULL', 'room is full');
    }
    if (this.phase !== 'lobby') {
      throw new RoomError('ALREADY_STARTED', 'game already started');
    }
    const seat = this.seats.length;
    const token = existingToken ?? this.deps.mintToken();
    this.seats.push({
      seat,
      name,
      kindBase: 'human',
      ready: false,
      connId,
      aiTakingOver: false,
      downSinceMs: null,
      token,
      discipline: 0,
    });
    this.lastHumanLiveAtMs = this.deps.now();
    this.pushRoomState();
    return { seat, token, reclaimed: false };
  }

  attach(seat: number, connId: string): { seat: number; token: string } {
    const s = this.seats[seat];
    if (!s) throw new RoomError('NO_SEAT', 'seat does not exist');
    if (s.kindBase !== 'human') throw new RoomError('NOT_HUMAN', 'seat is not human');

    // If a previous connection holds this seat, kick it. The daemon owns the
    // actual socket close; here we just emit the bye.
    if (s.connId !== null && s.connId !== connId) {
      this.deps.bus({ t: 'bye', connId: s.connId, reason: 'replaced' });
    }
    s.connId = connId;
    s.downSinceMs = null;
    this.lastHumanLiveAtMs = this.deps.now();

    // If they reconnected while AI was taking over their turn, do NOT yank
    // control: leave aiTakingOver true; the next endTurn flips it off. They
    // still receive game-state pushes via their new connId.
    if (!s.aiTakingOver) {
      this.cancelTimers((t) => t.kind === 'reminder' || t.kind === 'expire');
    }

    if (this.phase === 'playing') this.pushGameState();
    else this.pushRoomState();
    return { seat, token: s.token };
  }

  detach(seat: number): void {
    const s = this.seats[seat];
    if (!s || s.kindBase !== 'human') return;
    if (s.connId === null) return;
    s.connId = null;
    s.downSinceMs = this.deps.now();
    this.transferHostIfNeeded();

    if (
      this.phase === 'playing' &&
      this.state &&
      this.state.current === seat &&
      !s.aiTakingOver
    ) {
      this.startGraceTimer(seat, this.deps.now());
    }

    if (this.phase === 'playing') this.pushGameState();
    else this.pushRoomState();
  }

  addAiSeat(callerConnId: string, discipline = DEFAULT_AI_DISCIPLINE): void {
    this.requireHost(callerConnId);
    if (this.phase !== 'lobby') throw new RoomError('NOT_LOBBY', 'lobby only');
    if (this.seats.length >= MAX_SEATS) throw new RoomError('ROOM_FULL', 'room is full');
    const seat = this.seats.length;
    this.seats.push({
      seat,
      name: 'AI (' + discipline.toFixed(1) + ')',
      kindBase: 'ai',
      ready: true,
      connId: null,
      aiTakingOver: false,
      downSinceMs: null,
      token: '',
      discipline,
    });
    this.pushRoomState();
  }

  removeSeat(callerConnId: string, seat: number): void {
    this.requireHost(callerConnId);
    if (this.phase !== 'lobby') throw new RoomError('NOT_LOBBY', 'lobby only');
    const s = this.seats[seat];
    if (!s) throw new RoomError('NO_SEAT', 'seat does not exist');
    if (s.kindBase === 'human' && s.connId !== null) {
      this.deps.bus({ t: 'bye', connId: s.connId, reason: 'kicked' });
    }
    this.seats.splice(seat, 1);
    for (let i = 0; i < this.seats.length; i++) this.seats[i].seat = i;
    if (this.host >= this.seats.length) this.host = Math.max(0, this.seats.length - 1);
    this.transferHostIfNeeded();
    this.pushRoomState();
  }

  setReady(callerConnId: string, ready: boolean): void {
    const idx = this.seatByConnId(callerConnId);
    if (idx === -1) throw new RoomError('NOT_IN_ROOM', 'caller is not seated');
    const s = this.seats[idx];
    if (s.kindBase !== 'human') throw new RoomError('NOT_HUMAN', 'seat is not human');
    s.ready = ready;
    this.pushRoomState();
  }

  start(callerConnId: string): void {
    this.requireHost(callerConnId);
    if (this.phase !== 'lobby') throw new RoomError('NOT_LOBBY', 'lobby only');
    if (this.seats.length < MIN_SEATS) throw new RoomError('NOT_ENOUGH_SEATS', 'need at least 2');
    for (const s of this.seats) {
      if (s.kindBase === 'human' && !s.ready) {
        throw new RoomError('NOT_READY', 'not all humans are ready');
      }
    }
    this.phase = 'playing';
    this.state = initialState(this.seats.map((s) => s.name));
    this.pushRoomState();
    this.pushGameState();
    this.maybeRunAi();
  }

  // ─── game ─────────────────────────────────────────────────────────────────
  submitAction(callerConnId: string, action: Action): void {
    if (this.phase !== 'playing' || !this.state) {
      throw new RoomError('NOT_PLAYING', 'game not in progress');
    }
    const idx = this.seatByConnId(callerConnId);
    if (idx === -1) throw new RoomError('NOT_IN_ROOM', 'caller is not seated');
    if (idx !== this.state.current) throw new RoomError('NOT_YOUR_TURN', 'wait your turn');
    const s = this.seats[idx];
    if (s.aiTakingOver) throw new RoomError('AI_FINISHING', 'AI is finishing the turn');
    this.applyAction(action);
  }

  // ─── timers ───────────────────────────────────────────────────────────────
  tick(nowMs: number): void {
    if (this.reaped) return;
    if (this.phase !== 'over' && nowMs - this.lastHumanLiveAtMs >= IDLE_REAP_MS) {
      this.reap();
      return;
    }
    let fired = true;
    while (fired) {
      fired = false;
      for (let i = 0; i < this.timers.length; i++) {
        const t = this.timers[i];
        if (t.fireAtMs <= nowMs) {
          this.timers.splice(i, 1);
          this.fireTimer(t, nowMs);
          fired = true;
          break;
        }
      }
    }
  }

  // ─── helpers ──────────────────────────────────────────────────────────────
  liveConnIds(): string[] {
    const ids: string[] = [];
    for (const s of this.seats) {
      if (s.kindBase === 'human' && s.connId !== null) ids.push(s.connId);
    }
    return ids;
  }

  seatByConnId(connId: string): number {
    for (const s of this.seats) {
      if (s.kindBase === 'human' && s.connId === connId) return s.seat;
    }
    return -1;
  }

  isHost(connId: string): boolean {
    const idx = this.seatByConnId(connId);
    return idx !== -1 && idx === this.host;
  }

  hasAnyHumans(): boolean {
    return this.seats.some((s) => s.kindBase === 'human');
  }

  // ─── private ──────────────────────────────────────────────────────────────
  private seatKind(s: SeatRecord): SeatKind {
    if (s.kindBase === 'ai') return 'ai';
    return s.aiTakingOver ? 'ai-takeover' : 'human';
  }

  private requireHost(connId: string): void {
    if (!this.isHost(connId)) throw new RoomError('NOT_HOST', 'host only');
  }

  // Sticky host transfer: if current host has no connection, move to the
  // lowest-seat live human. Once moved, it does NOT revert on reconnect.
  private transferHostIfNeeded(): void {
    const cur = this.seats[this.host];
    if (cur && (cur.kindBase === 'ai' || cur.connId !== null)) return;
    const lowest = this.seats.findIndex(
      (s) => s.kindBase === 'human' && s.connId !== null,
    );
    if (lowest !== -1) this.host = lowest;
  }

  private buildSeatViews(): SeatView[] {
    return this.seats.map((s) => ({
      seat: s.seat,
      name: s.name,
      kind: this.seatKind(s),
      ready: s.ready,
      connected: s.kindBase === 'ai' ? true : s.connId !== null,
    }));
  }

  private pushRoomState(): void {
    const payload: S2C = {
      v: 1,
      t: 'ROOM_STATE',
      code: this.code,
      host: this.host,
      phase: this.phase,
      seats: this.buildSeatViews(),
    };
    for (const id of this.liveConnIds()) {
      this.deps.bus({ t: 'send', connId: id, msg: payload });
    }
  }

  private pushGameState(lastEvent?: GameEvent): void {
    if (!this.state) return;
    const seats = this.buildSeatViews();
    for (const s of this.seats) {
      if (s.kindBase !== 'human' || s.connId === null) continue;
      const msg: S2C = {
        v: 1,
        t: 'GAME_STATE',
        state: this.state,
        viewerSeat: s.seat,
        seats,
        lastEvent,
      };
      this.deps.bus({ t: 'send', connId: s.connId, msg });
    }
  }

  private classifyEvent(prev: State, next: State): GameEvent | undefined {
    if (next.current === prev.current && next.phase !== 'over') return undefined;
    const actor = prev.current;
    const prevTiles = prev.players[actor].tiles.length;
    const nextTiles = next.players[actor].tiles.length;
    const prevCenter = prev.centerTiles.length;
    const nextCenter = next.centerTiles.length;
    if (nextTiles > prevTiles) {
      return nextCenter < prevCenter ? 'banked' : 'stolen';
    }
    if (
      nextTiles < prevTiles ||
      nextCenter < prevCenter ||
      (prev.setAside.length > 0 && nextCenter >= prevCenter)
    ) {
      return 'busted';
    }
    return undefined;
  }

  private applyAction(action: Action): void {
    if (!this.state) return;
    const prev = this.state;
    const next = step(prev, action, this.deps.rng);
    this.state = next;
    const evt = this.classifyEvent(prev, next);
    const turnEnded = next.current !== prev.current || next.phase === 'over';

    if (turnEnded) {
      // If the seat that just acted was a human under ai-takeover, flip
      // takeover off and route to either live (if reconnected) or down.
      const actor = this.seats[prev.current];
      if (actor && actor.kindBase === 'human' && actor.aiTakingOver) {
        actor.aiTakingOver = false;
        // If still no connId, mark down so the next time their turn comes
        // around we re-enter the grace flow.
        if (actor.connId === null) {
          actor.downSinceMs = this.deps.now();
        }
        this.pushRoomState();
      }
    }

    if (next.phase === 'over') {
      this.phase = 'over';
      this.pushGameState(evt);
      this.pushRoomState();
      return;
    }
    this.pushGameState(evt);
    this.maybeRunAi();
  }

  // After any state transition: if the current seat needs the server to
  // play for it, schedule an AI step. Also: if the current seat is a
  // human who is `down` (turn came around while they were dropped), start
  // the grace timer afresh.
  private maybeRunAi(): void {
    if (this.phase !== 'playing' || !this.state) return;
    const cur = this.seats[this.state.current];
    if (!cur) return;

    if (cur.kindBase === 'ai' || cur.aiTakingOver) {
      this.scheduleAiStep();
      return;
    }
    if (cur.kindBase === 'human' && cur.connId === null) {
      this.startGraceTimer(cur.seat, this.deps.now());
    }
  }

  private scheduleAiStep(): void {
    if (this.timers.some((t) => t.kind === 'ai-step')) return;
    this.timers.push({
      kind: 'ai-step',
      fireAtMs: this.deps.now() + AI_THINK_MS,
    });
  }

  private startGraceTimer(seat: number, nowMs: number): void {
    this.cancelTimers((t) => t.kind === 'reminder' || t.kind === 'expire');
    for (const id of this.liveConnIds()) {
      this.deps.bus({
        t: 'send',
        connId: id,
        msg: { v: 1, t: 'TURN_REMINDER', seat, secondsLeft: 15 },
      });
    }
    this.timers.push({ kind: 'reminder', fireAtMs: nowMs + REMINDER_EVERY_MS });
    this.timers.push({ kind: 'expire', fireAtMs: nowMs + GRACE_MS });
  }

  private fireTimer(t: Timer, nowMs: number): void {
    if (t.kind === 'ai-step') {
      this.runOneAiAction();
      return;
    }
    if (!this.state) return;
    const seat = this.state.current;
    const s = this.seats[seat];
    if (!s || s.kindBase !== 'human' || s.connId !== null || s.aiTakingOver) return;
    if (t.kind === 'reminder') {
      const downSince = s.downSinceMs ?? nowMs;
      const elapsed = nowMs - downSince;
      const secondsLeft = Math.max(0, Math.round((GRACE_MS - elapsed) / 1000));
      for (const id of this.liveConnIds()) {
        this.deps.bus({
          t: 'send',
          connId: id,
          msg: { v: 1, t: 'TURN_REMINDER', seat, secondsLeft },
        });
      }
      if (secondsLeft > 0) {
        this.timers.push({ kind: 'reminder', fireAtMs: nowMs + REMINDER_EVERY_MS });
      }
      return;
    }
    if (t.kind === 'expire') {
      s.aiTakingOver = true;
      this.pushRoomState();
      this.scheduleAiStep();
    }
  }

  private runOneAiAction(): void {
    if (this.phase !== 'playing' || !this.state) return;
    const seat = this.seats[this.state.current];
    if (!seat) return;
    const isAi = seat.kindBase === 'ai' || seat.aiTakingOver;
    if (!isAi) return;

    // Pause if no humans are watching live.
    const anyLiveHuman = this.seats.some(
      (s) => s.kindBase === 'human' && s.connId !== null,
    );
    if (!anyLiveHuman) return;

    const discipline = seat.kindBase === 'ai' ? seat.discipline : DEFAULT_AI_DISCIPLINE;
    const ai: Difficulty = { discipline };
    const action = decide(this.state, ai);
    this.applyAction(action);
  }

  private cancelTimers(pred: (t: Timer) => boolean): void {
    this.timers = this.timers.filter((t) => !pred(t));
  }

  private reap(): void {
    if (this.reaped) return;
    this.reaped = true;
    for (const s of this.seats) {
      if (s.kindBase === 'human' && s.connId !== null) {
        this.deps.bus({ t: 'bye', connId: s.connId, reason: 'room reaped' });
      }
    }
    this.phase = 'over';
    this.timers = [];
  }
}

export class RoomError extends Error {
  constructor(public code: string, message: string) {
    super(code + ': ' + message);
  }
}
