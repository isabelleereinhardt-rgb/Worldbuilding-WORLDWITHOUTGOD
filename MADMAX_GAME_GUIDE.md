# 🎴 Mad Max: Wasteland Brawl

A chaotic, Mad Max-inspired **16-player card-based board game brawler** for Roblox.
Players draft combat cards, roll dice to race along a 60-tile trap-laced board through
three escalating danger zones, and use attacks, traps, buffs, and counters to be the
**last one standing**, score the **most kills**, or be the **first to reach the Thunderdome
finish line**.

Built from the complete game design document — this is the full **Phase 1 Core MVP**:
all 70 cards functional, the 60-tile board, 4-group simultaneous turns, combat with
reaction windows, the draft system, win conditions, and the full in-game HUD.

---

## 🚀 Getting it into Roblox Studio

This project uses the standard [Rojo](https://rojo.space) layout. Two ways to run it:

### Option A — Rojo (recommended)

1. Install [Roblox Studio](https://create.roblox.com/) and [Rojo](https://rojo.space/docs/v7/getting-started/installation/) (VS Code extension or CLI).
2. From this folder run:
   ```bash
   rojo serve
   ```
3. In Studio, open a new Baseplate place, install the Rojo plugin, and click **Connect**.
4. The board builds itself when you press **Play**. Use **Clients and Servers** test
   mode (2+ players) — a match needs at least 2 players to start.

### Option B — Manual copy (no tools needed)

Recreate this structure in Studio's Explorer, copying each file's contents into a
script of the matching type:

| File | Studio location | Instance type |
|---|---|---|
| `src/shared/*.luau` | `ReplicatedStorage/Shared/` | ModuleScript (named without extension) |
| `src/server/init.server.luau` | `ServerScriptService/Server` | **Script** |
| `src/server/*.luau` (the rest) | children of that Script | ModuleScript |
| `src/client/init.client.luau` | `StarterPlayer/StarterPlayerScripts/Client` | **LocalScript** |
| `src/client/*.luau` (the rest) | children of that LocalScript | ModuleScript |

> With Rojo, a folder containing `init.server.luau` becomes a Script whose children
> are the other modules in that folder — mirror that when copying manually.

---

## 🎮 How a match plays

1. **Lobby** — waits for 2+ players, then a 15-second countdown.
2. **Draft** — 3 rounds of picking 1 card from a 15-card weighted pool (10s each),
   then 7 random cards fill your hand to 10.
3. **Playing** — 6-minute match. Players are split into 4 groups; each group's turn runs:
   - 🎲 **Roll** (2s) — everyone in the group rolls 1-6 simultaneously
   - 🏃 **Movement** (3s) — avatars walk the board tile-by-tile
   - ⚡ **Tile Effects** (2s) — heal / damage / bonus card / trap tiles fire
   - 🃏 **Action** (10s) — play cards; attacks open a **1-second counter window**
   - ⚔ **Resolution** — queued plays finish resolving
4. **Game over** — first to Tile 60 wins instantly; otherwise last standing; otherwise
   most kills at time-up. Scoreboard shows kills, damage, cards played, and Scrap.

**Death:** HP hits 0 **or** you run out of cards. Your killer takes your entire hand.
Dead players spectate in ghost mode.

## 🗺 The board

| Zone | Tiles | Theme | Danger |
|---|---|---|---|
| 1 | 1–20 | Wasteland Desert (sand) | Low |
| 2 | 21–45 | Scrapyard Industrial (corroded metal) | Medium |
| 3 | 46–60 | Thunderdome Arena (basalt) | High |

60 tiles in a snake layout: 39 safe, 5 heal (10-20 HP), 6 damage (10-15),
4 bonus-card, 6 pre-armed trap tiles, with Tile 60 as the 🏁 finish.

## 🃏 The 70-card pool

| Type | Unique | Copies | Total |
|---|---|---|---|
| Common Attack | 6 | ×5 | 30 |
| Uncommon Utility | 10 | ×1 | 10 |
| Trap | 10 | ×1 | 10 |
| Support & Buff | 10 | ×1 | 10 |
| Rare | 10 | ×1 | 10 |

Every card from the design document is implemented — from Rusty Spanner to
Phoenix Flame. See `src/shared/CardDatabase.luau`.

## 📁 Code map

```
src/
├── shared/                     (ReplicatedStorage/Shared)
│   ├── Config.luau             All tunable numbers: timers, HP, zones, weights
│   ├── CardDatabase.luau       All 70 cards as data
│   ├── TileDatabase.luau       The 60-tile board layout
│   └── Remotes.luau            RemoteEvent registry
├── server/                     (ServerScriptService/Server)
│   ├── init.server.luau        Bootstrap: wires managers, routes client requests
│   ├── GameManager.luau        Match state machine, timers, win conditions
│   ├── TurnManager.luau        4 groups × 5 phases, action queue
│   ├── BoardManager.luau       Physical board build, movement, tile effects, traps
│   ├── CardManager.luau        Draft, dealing, playing cards, every card effect
│   ├── CombatManager.luau      Damage formula, targeting, reaction window, death
│   └── PlayerDataManager.luau  HP / hand / buffs / statuses + replication
└── client/                     (StarterPlayerScripts/Client)
    ├── init.client.luau        Event handling, hand clicks, targeting, spectate
    ├── UI.luau                 Full HUD built in code (wasteland-themed)
    └── CameraController.luau   Board-game camera (follow + zoom, spectator)
```

## 🔧 Design decisions worth knowing

- **All combat is server-authoritative.** Clients only send *requests*
  (play card N, pick card X); the server validates turn phase, targeting
  (nearest-enemy rule with HP tiebreaker), buff stacking rules, and hand limits.
- **Damage formula** is straight from the doc: `Final = Base × (1 + Buff%) + Flat`,
  absorbed by shields → temp HP → real HP, with Iron Will and Phoenix Flame checked
  at the kill step.
- **Traps are never hidden** — placing one shows a 🪤 marker to everyone, and
  triggering has the doc's 1-second telegraph before damage lands.
- **Board logic is data, visuals are generated.** `TileDatabase` is the truth;
  `BoardManager.buildBoard()` constructs the parts at runtime, so re-theming zones
  or moving special tiles is a data edit.

## 🗺 Roadmap (from the design doc)

- ✅ **Phase 1 — Core MVP** (this)
- ⬜ **Phase 2 — Polish & Spectator:** chaos-mode voting, cheering, card VFX/SFX
- ⬜ **Phase 3 — Economy:** DataStore persistence for Scrap, crafting, daily challenges
- ⬜ **Phase 4 — Monetization:** card packs and gamepasses

Scrap is already earned and shown on the scoreboard so Phase 3 can build on it.
