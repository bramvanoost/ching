import { describe, expect, it } from 'vitest';
import {
  FrameDecoder,
  ProtocolError,
  encode,
  type C2S,
  type S2C,
} from '../src/net/protocol.js';

describe('protocol', () => {
  it('round-trips every C2S type', () => {
    const samples: C2S[] = [
      { v: 1, t: 'HELLO', name: 'alice' },
      { v: 1, t: 'HELLO', name: 'alice', token: 'tok-1' },
      { v: 1, t: 'CREATE_ROOM' },
      { v: 1, t: 'JOIN_ROOM', code: 'X7K3' },
      { v: 1, t: 'ADD_AI_SEAT' },
      { v: 1, t: 'ADD_AI_SEAT', discipline: 0.8 },
      { v: 1, t: 'REMOVE_SEAT', seat: 2 },
      { v: 1, t: 'READY', ready: true },
      { v: 1, t: 'START' },
      { v: 1, t: 'ACTION', action: { type: 'ROLL' } },
      { v: 1, t: 'ACTION', action: { type: 'PICK', face: 6 } },
      { v: 1, t: 'ACTION', action: { type: 'STOP' } },
      { v: 1, t: 'LEAVE' },
    ];
    for (const msg of samples) {
      const d = new FrameDecoder();
      const decoded = d.push(encode(msg));
      expect(decoded).toEqual([msg]);
    }
  });

  it('round-trips every S2C type', () => {
    const samples: S2C[] = [
      { v: 1, t: 'WELCOME', token: 'tok-2' },
      { v: 1, t: 'WELCOME', token: 'tok-3', seatHint: { code: 'X7K3', seat: 1 } },
      {
        v: 1,
        t: 'ROOM_STATE',
        code: 'X7K3',
        host: 0,
        phase: 'lobby',
        seats: [
          { seat: 0, name: 'alice', kind: 'human', ready: true, connected: true },
          { seat: 1, name: 'AI (0.6)', kind: 'ai', ready: true, connected: true },
        ],
      },
      { v: 1, t: 'TURN_REMINDER', seat: 1, secondsLeft: 15 },
      { v: 1, t: 'ERROR', code: 'NOT_YOUR_TURN', message: 'wait' },
      { v: 1, t: 'BYE', reason: 'replaced' },
    ];
    for (const msg of samples) {
      const d = new FrameDecoder();
      expect(d.push(encode(msg))).toEqual([msg]);
    }
  });

  it('decodes one JSON split across two chunks', () => {
    const d = new FrameDecoder();
    const wire = encode({ v: 1, t: 'CREATE_ROOM' });
    const mid = Math.floor(wire.length / 2);
    expect(d.push(wire.slice(0, mid))).toEqual([]);
    expect(d.push(wire.slice(mid))).toEqual([{ v: 1, t: 'CREATE_ROOM' }]);
  });

  it('decodes multiple JSONs in a single chunk', () => {
    const d = new FrameDecoder();
    const wire =
      encode({ v: 1, t: 'CREATE_ROOM' }) +
      encode({ v: 1, t: 'READY', ready: true });
    expect(d.push(wire)).toEqual([
      { v: 1, t: 'CREATE_ROOM' },
      { v: 1, t: 'READY', ready: true },
    ]);
  });

  it('throws ProtocolError on malformed JSON', () => {
    const d = new FrameDecoder();
    expect(() => d.push('not json\n')).toThrow(ProtocolError);
  });

  it('throws ProtocolError on missing version', () => {
    const d = new FrameDecoder();
    expect(() => d.push(JSON.stringify({ t: 'HELLO', name: 'a' }) + '\n')).toThrow(
      /BAD_VERSION/,
    );
  });

  it('throws ProtocolError on missing type', () => {
    const d = new FrameDecoder();
    expect(() => d.push(JSON.stringify({ v: 1 }) + '\n')).toThrow(/BAD_MESSAGE/);
  });
});
