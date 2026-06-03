import { beforeEach, describe, expect, it } from 'vitest';
import type { Face, Rng } from '../src/engine.js';
import { Room, RoomError, type RoomEvent } from '../src/net/room.js';
import type { S2C } from '../src/net/protocol.js';

function rngForFaces(faces: Face[]): Rng {
  let i = 0;
  return () => {
    const f = faces[i % faces.length];
    i++;
    return (f - 1) / 6 + 0.0001;
  };
}

function mkRoom(opts: { rng?: Rng; nowStart?: number } = {}): {
  room: Room;
  events: RoomEvent[];
  setNow: (ms: number) => void;
  byes: { connId: string; reason: string }[];
  sends: { connId: string; msg: S2C }[];
} {
  let now = opts.nowStart ?? 0;
  const events: RoomEvent[] = [];
  const room = new Room('TEST', {
    rng: opts.rng ?? Math.random,
    now: () => now,
    bus: (e) => events.push(e),
    mintToken: (() => {
      let n = 0;
      return () => 'tok-' + ++n;
    })(),
  });
  return {
    room,
    events,
    setNow: (ms) => { now = ms; },
    get byes() {
      return events.filter((e): e is { t: 'bye'; connId: string; reason: string } => e.t === 'bye');
    },
    get sends() {
      return events.filter((e): e is { t: 'send'; connId: string; msg: S2C } => e.t === 'send');
    },
  };
}

describe('Room lobby', () => {
  let h: ReturnType<typeof mkRoom>;
  beforeEach(() => { h = mkRoom(); });

  it('joins up to 4 humans and rejects the 5th', () => {
    h.room.joinHuman('a', 'c1');
    h.room.joinHuman('b', 'c2');
    h.room.joinHuman('c', 'c3');
    h.room.joinHuman('d', 'c4');
    expect(() => h.room.joinHuman('e', 'c5')).toThrow(RoomError);
    expect(h.room.seats.length).toBe(4);
  });

  it('host adds an AI seat (host only)', () => {
    h.room.joinHuman('a', 'c1');
    h.room.joinHuman('b', 'c2');
    h.room.addAiSeat('c1', 0.8);
    expect(h.room.seats[2].kindBase).toBe('ai');
    expect(h.room.seats[2].discipline).toBe(0.8);
    expect(() => h.room.addAiSeat('c2')).toThrow(/NOT_HOST/);
  });

  it('host transfer on disconnect is sticky', () => {
    h.room.joinHuman('a', 'c1');
    h.room.joinHuman('b', 'c2');
    expect(h.room.host).toBe(0);
    h.room.detach(0);
    expect(h.room.host).toBe(1);
    // Original host (seat 0) reconnects — host does NOT revert.
    h.room.joinHuman('a', 'c1b', 'tok-1');
    expect(h.room.host).toBe(1);
  });

  it('START rejects if not all humans are ready', () => {
    h.room.joinHuman('a', 'c1');
    h.room.joinHuman('b', 'c2');
    h.room.setReady('c1', true);
    expect(() => h.room.start('c1')).toThrow(/NOT_READY/);
    h.room.setReady('c2', true);
    expect(() => h.room.start('c1')).not.toThrow();
  });

  it('START rejects with fewer than 2 seats', () => {
    h.room.joinHuman('a', 'c1');
    h.room.setReady('c1', true);
    expect(() => h.room.start('c1')).toThrow(/NOT_ENOUGH_SEATS/);
  });
});

describe('Room turn enforcement', () => {
  it('rejects an ACTION from the non-current seat', () => {
    const rng = rngForFaces([6, 5, 5, 5, 5, 5, 5, 5]);
    const h = mkRoom({ rng });
    h.room.joinHuman('a', 'c1');
    h.room.joinHuman('b', 'c2');
    h.room.setReady('c1', true);
    h.room.setReady('c2', true);
    h.room.start('c1');
    expect(h.room.state!.current).toBe(0);
    expect(() => h.room.submitAction('c2', { type: 'ROLL' })).toThrow(/NOT_YOUR_TURN/);
    expect(() => h.room.submitAction('c1', { type: 'ROLL' })).not.toThrow();
  });
});

describe('Room disconnect grace cadence', () => {
  it('pushes TURN_REMINDER at 15, 10, 5 and flips to ai-takeover at expiry', () => {
    const rng = rngForFaces([6, 5, 5, 5, 5, 5, 5, 5]);
    const h = mkRoom({ rng, nowStart: 0 });
    h.room.joinHuman('a', 'c1');
    h.room.joinHuman('b', 'c2');
    h.room.setReady('c1', true);
    h.room.setReady('c2', true);
    h.room.start('c1');

    // It's seat 0's turn. Drop seat 0.
    h.events.length = 0;
    h.room.detach(0);

    // Initial reminder at t=0 with secondsLeft=15
    const reminders0 = h.sends.filter((s) => s.msg.t === 'TURN_REMINDER');
    expect(reminders0).toHaveLength(1); // pushed once to seat 1
    expect((reminders0[0].msg as { secondsLeft: number }).secondsLeft).toBe(15);

    // Advance 5s -> reminder with secondsLeft=10
    h.events.length = 0;
    h.setNow(5_000);
    h.room.tick(5_000);
    const r1 = h.sends.filter((s) => s.msg.t === 'TURN_REMINDER');
    expect(r1).toHaveLength(1);
    expect((r1[0].msg as { secondsLeft: number }).secondsLeft).toBe(10);

    // Advance another 5s -> reminder with secondsLeft=5
    h.events.length = 0;
    h.setNow(10_000);
    h.room.tick(10_000);
    const r2 = h.sends.filter((s) => s.msg.t === 'TURN_REMINDER');
    expect(r2).toHaveLength(1);
    expect((r2[0].msg as { secondsLeft: number }).secondsLeft).toBe(5);

    // Advance to 15s -> seat flips to ai-takeover, AI scheduled
    h.events.length = 0;
    h.setNow(15_000);
    h.room.tick(15_000);
    expect(h.room.seats[0].aiTakingOver).toBe(true);

    // Tick past the 380ms AI think delay -> AI plays an action
    h.events.length = 0;
    h.setNow(15_000 + 380);
    h.room.tick(15_000 + 380);
    const gameStates = h.sends.filter((s) => s.msg.t === 'GAME_STATE');
    expect(gameStates.length).toBeGreaterThan(0);
  });

  it('reconnect during ai-takeover keeps AI in control until turn ends', () => {
    const rng = rngForFaces([6, 5, 5, 5, 5, 5, 5, 5]);
    const h = mkRoom({ rng, nowStart: 0 });
    h.room.joinHuman('a', 'c1');
    h.room.joinHuman('b', 'c2');
    h.room.setReady('c1', true);
    h.room.setReady('c2', true);
    h.room.start('c1');
    h.room.detach(0);
    h.setNow(15_000);
    h.room.tick(15_000);
    expect(h.room.seats[0].aiTakingOver).toBe(true);

    // Player a reconnects with their token, mid-turn.
    h.room.joinHuman('a', 'c1b', 'tok-1');
    expect(h.room.seats[0].aiTakingOver).toBe(true);
    // They cannot submit while AI is finishing.
    expect(() => h.room.submitAction('c1b', { type: 'ROLL' })).toThrow(/AI_FINISHING/);
  });

  it('reconnect outside the dropped seat\'s turn flips straight back to live', () => {
    const rng = rngForFaces([6, 5, 5, 5, 5, 5, 5, 5]);
    const h = mkRoom({ rng, nowStart: 0 });
    h.room.joinHuman('a', 'c1');
    h.room.joinHuman('b', 'c2');
    h.room.setReady('c1', true);
    h.room.setReady('c2', true);
    h.room.start('c1');
    // It's seat 0's turn. Drop seat 1 (not the active seat) -> no grace timer.
    h.room.detach(1);
    expect(h.room.seats[1].aiTakingOver).toBe(false);
    expect(h.room.seats[1].connId).toBeNull();
    // Reconnect.
    h.room.joinHuman('b', 'c2b', 'tok-2');
    expect(h.room.seats[1].connId).toBe('c2b');
    expect(h.room.seats[1].aiTakingOver).toBe(false);
  });
});

describe('Room reconnect token semantics', () => {
  it('reclaims a seat by token and emits BYE on the replaced connection', () => {
    const h = mkRoom();
    const r1 = h.room.joinHuman('alice', 'c1');
    expect(r1.reclaimed).toBe(false);
    // Same player connects again from a different socket.
    h.events.length = 0;
    const r2 = h.room.joinHuman('alice', 'c2', r1.token);
    expect(r2.reclaimed).toBe(true);
    expect(r2.seat).toBe(r1.seat);
    expect(h.byes).toContainEqual({ t: 'bye', connId: 'c1', reason: 'replaced' });
  });
});

describe('Room READY broadcast', () => {
  it('pushes ROOM_STATE to every live human seat after a READY, not just the caller', () => {
    const h = mkRoom();
    h.room.joinHuman('alice', 'c1');
    h.room.joinHuman('bob', 'c2');
    h.events.length = 0;

    h.room.setReady('c1', true);
    const afterAlice = h.sends.filter((s) => s.msg.t === 'ROOM_STATE');
    // BOTH connections must see Alice's ready flip.
    const toAlice = afterAlice.filter((s) => s.connId === 'c1');
    const toBob = afterAlice.filter((s) => s.connId === 'c2');
    expect(toAlice.length).toBeGreaterThan(0);
    expect(toBob.length).toBeGreaterThan(0);
    for (const s of [...toAlice, ...toBob]) {
      const msg = s.msg as Extract<S2C, { t: 'ROOM_STATE' }>;
      expect(msg.seats[0].ready).toBe(true);
      expect(msg.seats[1].ready).toBe(false);
    }

    h.events.length = 0;
    h.room.setReady('c2', true);
    const afterBob = h.sends.filter((s) => s.msg.t === 'ROOM_STATE');
    const toAlice2 = afterBob.filter((s) => s.connId === 'c1');
    const toBob2 = afterBob.filter((s) => s.connId === 'c2');
    expect(toAlice2.length).toBeGreaterThan(0);
    expect(toBob2.length).toBeGreaterThan(0);
    for (const s of [...toAlice2, ...toBob2]) {
      const msg = s.msg as Extract<S2C, { t: 'ROOM_STATE' }>;
      expect(msg.seats.every((seat) => seat.ready)).toBe(true);
    }

    // And now START actually unlocks (no NOT_READY thrown).
    expect(() => h.room.start('c1')).not.toThrow();
    expect(h.room.phase).toBe('playing');
  });
});

describe('Room intentional leave', () => {
  it('lobby LEAVE removes the seat from the room', () => {
    const h = mkRoom();
    h.room.joinHuman('alice', 'c1');
    h.room.joinHuman('bob', 'c2');
    expect(h.room.seats.length).toBe(2);

    h.room.leave('c2');

    expect(h.room.seats.length).toBe(1);
    expect(h.room.seats[0].name).toBe('alice');
  });

  it('in-game LEAVE converts the seat to a permanent AI seat with no TURN_REMINDER', () => {
    const rng = rngForFaces([6, 5, 5, 5, 5, 5, 5, 5]);
    const h = mkRoom({ rng, nowStart: 0 });
    h.room.joinHuman('alice', 'c1');
    h.room.joinHuman('bob', 'c2');
    h.room.setReady('c1', true);
    h.room.setReady('c2', true);
    h.room.start('c1');
    expect(h.room.state!.current).toBe(0);

    h.events.length = 0;
    h.room.leave('c1');  // alice quits intentionally on her own turn

    // Seat is now permanent AI, not a "disconnected human waiting for grace".
    expect(h.room.seats[0].kindBase).toBe('ai');
    expect(h.room.seats[0].connId).toBeNull();
    expect(h.room.seats[0].aiTakingOver).toBe(false);
    // No grace countdown started — leavers are gone for good.
    expect(h.sends.filter((s) => s.msg.t === 'TURN_REMINDER')).toHaveLength(0);

    // Even if we tick through the would-be 15s grace window, no reminders.
    h.setNow(15_000);
    h.room.tick(15_000);
    expect(h.sends.filter((s) => s.msg.t === 'TURN_REMINDER')).toHaveLength(0);
  });
});

describe('Room ai-takeover persists across rounds', () => {
  it('does not restart the 15s grace when the takeover seat\'s turn comes back', () => {
    // All-5s rng: every roll fills 8 dice with COIN (5). On any seat's turn,
    // PICK 5 -> diceInHand=0 -> auto-bank a tile -> turn ends in one action.
    const rng = rngForFaces([5, 5, 5, 5, 5, 5, 5, 5]);
    const h = mkRoom({ rng, nowStart: 0 });
    h.room.joinHuman('alice', 'c1');
    h.room.joinHuman('bob', 'c2');
    h.room.addAiSeat('c1', 0.6);  // host adds AI seat 2; we have 3 seats total
    h.room.setReady('c1', true);
    h.room.setReady('c2', true);
    h.room.start('c1');
    expect(h.room.state!.current).toBe(0);

    // Silent-drop alice on her turn -> grace expires -> ai-takeover.
    h.room.detach(0);
    h.setNow(15_000);
    h.room.tick(15_000);
    expect(h.room.seats[0].aiTakingOver).toBe(true);

    // Drive AI through alice's takeover turn.
    let t = 15_000;
    while (h.room.state!.current === 0 && t < 30_000) {
      t += 380;
      h.setNow(t);
      h.room.tick(t);
    }
    expect(h.room.state!.current).toBe(1);  // moved to bob

    // Clear send log so we can detect any NEW TURN_REMINDER for alice's seat.
    h.events.length = 0;

    // Bob plays his turn: ROLL -> PICK 5 -> auto-bank -> turn ends.
    h.room.submitAction('c2', { type: 'ROLL' });
    h.room.submitAction('c2', { type: 'PICK', face: 5 });
    expect(h.room.state!.current).toBe(2);  // AI carol

    // Drive carol (AI seat) through her turn.
    while (h.room.state!.current === 2 && t < 60_000) {
      t += 380;
      h.setNow(t);
      h.room.tick(t);
    }
    expect(h.room.state!.current).toBe(0);  // back to alice

    // The bug: a fresh 15s countdown fires every time alice's turn comes
    // back. The fix: alice stays in ai-takeover, so maybeRunAi schedules
    // an AI step instead of starting another grace timer.
    expect(h.sends.filter((s) => s.msg.t === 'TURN_REMINDER')).toHaveLength(0);
    expect(h.room.seats[0].aiTakingOver).toBe(true);
  });
});

describe('Room idle reaper', () => {
  it('reaps a paused room with 1 human + 1 AI 30 minutes after the human drops', () => {
    const h = mkRoom({ nowStart: 0 });
    h.room.joinHuman('a', 'c1');
    h.room.addAiSeat('c1', 0.6);
    h.room.setReady('c1', true);
    h.room.start('c1');
    h.room.detach(0);
    h.setNow(29 * 60 * 1000 + 59 * 1000);
    h.room.tick(29 * 60 * 1000 + 59 * 1000);
    expect(h.room.reaped).toBe(false);
    h.setNow(30 * 60 * 1000);
    h.room.tick(30 * 60 * 1000);
    expect(h.room.reaped).toBe(true);
  });

  it('reaps a room mid-ai-takeover that has no live humans', () => {
    const rng = rngForFaces([6, 5, 5, 5, 5, 5, 5, 5]);
    const h = mkRoom({ rng, nowStart: 0 });
    h.room.joinHuman('a', 'c1');
    h.room.joinHuman('b', 'c2');
    h.room.setReady('c1', true);
    h.room.setReady('c2', true);
    h.room.start('c1');
    // Drop both humans. Seat 0 is active -> grace -> ai-takeover.
    h.room.detach(0);
    h.room.detach(1);
    h.setNow(15_000);
    h.room.tick(15_000);
    expect(h.room.seats[0].aiTakingOver).toBe(true);
    // Advance to 30 min -> reaped regardless of ai-takeover state.
    h.setNow(30 * 60 * 1000);
    h.room.tick(30 * 60 * 1000);
    expect(h.room.reaped).toBe(true);
  });
});
