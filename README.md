# Bug Game (working title)

An asymmetric online multiplayer game in 3D. One player is an exterminator working the night shift at a diner, and the other players are cockroaches trying to steal enough food to survive. It's being built for PC and Steam by a two-person team.

**Status: in development** · Godot 4.7 and GDScript · Online multiplayer (ENet, with Steam networking planned) · Co-developed under Wandering Turtle Games

> This repository is a **source-code sample** for portfolio review. Art, audio, scenes, and third-party add-ons are not included. See [NOTICE.md](NOTICE.md).

---

## Highlights

- **Networked multiplayer:** Host and client sessions over ENet, with each player owning their own movement and camera, synced player rosters, late-join handling, and clean disconnects.
- **Gameplay systems built for the network:** The exterminator's shotgun (pellet spread, ammo, recoil) and gas sprayer (limited fuel, cone damage, refills from the truck), plus cockroach climbing and wall crawling, carrying and throwing food, hiding spots, and kitchen hazards like the oven.
- **38 headless test scripts,** including networked tests that start a real host and client on localhost to check that weapons, climbing, hazards, food supply, and returns home behave the same for every player.
- **Pre-push smoke test:** `net_smoke_test.gd` checks the input map, both spawn paths, camera ownership, synced movement, and disconnect cleanup. It must print `SMOKE TEST: PASS` before code is pushed.
- **Team workflow:** Shared written rules for the codebase, Conventional Commits, a linear git history, and a documented decision log, so two developers (and their AI coding agents) can work in the same codebase without stepping on each other.

## Testing multiplayer alone

A launcher opens one host window and as many client windows as needed, all on localhost:

```bash
godot --headless --path . --script res://scripts/tools/local_multiplayer_launcher.gd -- --clients=3
```

A built-in dev room provides repeatable test stations for each mechanic. A solo test lab adds scripted bot opponents and clock controls, so mechanics can be tuned without a second person.

## Code layout

| Folder | What's in it |
|---|---|
| `scripts/game/` | Players, weapons, roach movement and combat, the food system, diner layout, hazards, dev room |
| `scripts/managers/` | Session and network management |
| `scripts/ui/` | Menu, food HUD, solo test HUD |
| `scripts/tools/` | Headless tests, the local multiplayer launcher, and procedural asset builders |

## Tech

Godot 4.7 · GDScript · ENet multiplayer · GodotSteam (planned) · headless automated testing · AI-assisted development with Claude Code
