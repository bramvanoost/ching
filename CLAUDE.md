# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## CHING

A push-your-luck dice game. Collect coins, bank them as tiles, steal rivals' tiles when you hit their exact number. Get greedy and bust, you lose a tile. 80s/8-bit terminal aesthetic. Signature payoff sound: ka-ching. (Mechanics inspired by Regenwormen/Heckmeck, reskinned, original name + theme.)

## Architecture (do NOT violate)

- `src/engine.ts` is PURE: `(state, action, rng) => newState`. No I/O, no rendering, no `Date.now`/`Math.random` inside, all randomness via the injected `rng`. This is what keeps multiplayer + mobile a port, not a rewrite.
- `src/ai.ts` depends ONLY on engine. Decides PICK + STOP/ROLL. Difficulty via a single `discipline` knob (0 = greedy, 1 = cautious). No I/O.
- `src/cli.ts` is a SWAPPABLE renderer (ANSI/terminal). A future web/mobile shell imports the SAME engine + ai. Never put game rules in the renderer.
- Dice rolls are the only randomness and MUST flow through injected `rng` so a server can own them (fair, cheat-proof) in multiplayer.

## Domain language

- `coins` = the collectible (face value 1-5; the COIN face = 5)
- `tiles` = banked stacks worth 1-4 coins, numbered 21-36
- "ching" = successful bank | "bust" = greedy fail, return top tile AND burn the highest remaining center tile (Heckmeck-style depletion, prevents stalemates)
- "steal" = land on a rival's exact top-tile number, take it

## Commands

- `npm run play` — play in terminal vs AI
- `npm test` — engine + AI tests

## Definition of done (verify, don't assume)

- `npm test` green.
- Regression: 200-game AI-vs-AI sim terminates cleanly AND higher discipline beats lower discipline over the sample (proves AI tiers aren't cosmetic).
- No `Math.random`/`Date` references inside `engine.ts` or `ai.ts`.

## Roadmap (build order)

1. Solo vs AI + local pass-and-play (free multiplayer, no backend).
2. Same engine on a server (PartyKit/Colyseus or a Pi over ssh). Server owns RNG. Disconnect -> AI takes the seat.
3. Accounts/leaderboards only if retention justifies it.

## Conventions

- TypeScript strict, no `any` in engine/ai.
- Engine stays framework-free and dependency-free.
- Commits imperative mood, <=72 chars.
