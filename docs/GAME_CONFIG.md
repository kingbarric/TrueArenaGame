# TrueArena — Game Config & Twist Catalog

> **One game, one engine, config-driven.** TrueArena's flagship module is the
> *Traitors and Faithful* social-deduction engine. It has no "game types" in code —
> every mode (Classic Conspiracy, Midnight Heist, …) is a **named preset `GameConfig`
> stored as data**, and a host can compose a **custom game** from the same fixed
> catalog. This is composition of an enumerated, versioned set of toggles — **not**
> rule-scripting (Build Brief §2 still holds).
>
> Source of truth for the rules: `Traitors_and_Faithful_Game_Rules_and_Host_Script.docx`.

---

## 1. How it fits together

```
GameConfig  ── resolved at GAME_START ──►  TrueArenaModule reducer
   ▲                                          │ reads config.* on every phase
   │ loaded from                              │ checks config.twists[id] before each hook
   │
game_config_preset  (Postgres, jsonb)
   ├─ scope = builtin   → the 5 shipped modes (seeded, immutable)
   ├─ scope = group     → a Group's saved custom setups
   └─ scope = user      → a host's personal saved setups
```

- **Adding a new mode later** = insert another `builtin` preset row. No engine change.
- **Custom game** = host edits a preset in the lobby → the result is a `GameConfig`;
  "Save" writes a `user`/`group` preset row.
- Every `GameConfig` carries `catalogVersion`. The reducer refuses a config whose
  version it doesn't understand; migrations bump the version and provide an upgrade map.

---

## 2. Phase model (updated)

```
Lobby
RoleReveal
┌─ Night ──────────────── traitors act privately (kill / poison / shield / skip)
│  MorningReveal ──────── announce the eliminated player; reveal role per policy;
│                         twist outputs surface here (Last Will, Silent Witness…)
│  RoundTable ─────────── open discussion; host moderation
│  Vote ───────────────── one locked pick per living player
│  VoteReview ─────────── sequential / all-at-once — SUPPRESSED once ≤ endgameVeil
│  Elimination ────────── remove the chosen player; reveal role per policy
│  WinCheck ───────────── faithful / traitor / Hidden Legacy checks
└─ (repeat)
FinalFire ──────────────── at 3 players: banish one, or end (traitor alive → traitors win)
Results ────────────────── full reveal: roles, hidden ballots, shields, poisons, recruitment
```

Two additions vs the original brief:

- **MorningReveal** is now a distinct phase (was folded into the start of discussion).
- **Veiled Endgame** is not a phase — it's a *mode* `VoteReview`/`Elimination` enter
  once `livingPlayers ≤ endgameVeil`: emit only `VOTE_LOCKED`, `ALL_VOTES_IN`, and the
  eliminated player; the full ballot history is released only on the `Results` screen.

---

## 3. `GameConfig` shape

Annotated (JSON5). Absent optional keys take the documented default.

```json5
{
  "catalogVersion": 1,
  "preset": "blood_moon",            // provenance label; "custom" once edited off a preset

  "table": {
    "players": 10,
    "minPlayers": 8,                 // from the mode
    "maxPlayers": 14,                // from the mode
    "adminOverride": false,          // true = allow 4..20; host must accept the balance warning
    "traitorCurve": [[8, 3]],        // [[fromPlayers, traitorCount], ...] ascending; resolved to int at start
  },

  "timers": {                        // seconds
    "night": 60,                     // 30..120
    "roundTable": 300,               // 60..600
    "vote": 60,                      // 30..90
    "defense": 60                    // used by Secret Accusation / Trial of Two
  },

  "nightKill": {
    "openingNight": "on",            // "on" | "off"  (Final Gambit = "off")
    "doubleAfterRound": null,        // int R → double murder allowed after round R; null = never
    "allowSkip": false,              // traitors may skip ONE murder across the whole game
    "requireTraitorConsensus": false // all traitors must confirm before the night clock ends
  },

  "revealOnElimination": "always",   // "always" | "never" | "alternating" (alternating starts public)

  "tieBreak": "revote",              // see §4
  "secondTie": "no_elimination",     // only consulted when tieBreak === "revote"
  "suddenDeathSeconds": 30,

  "afk": "abstain",                  // "abstain" | "host_assigns"
  "voteReveal": "sequential",        // "sequential" | "all_at_once"
  "endgameVeil": "final_4",          // "final_4" | "final_5" | "final_6" | "off"

  "twists": {                        // key present = enabled; value = that twist's params
    "poisoned_gift": { "uses": 1, "announceClaim": true, "hideClaimant": true }
  },

  "finalFire": { "atPlayers": 3, "allowEndEarly": true }
}
```

### 4. Enumerations

| Field | Values |
|---|---|
| `nightKill.openingNight` | `on`, `off` |
| `revealOnElimination` | `always`, `never`, `alternating` |
| `tieBreak` | `revote`, `no_elimination`, `random`, `sudden_death`, `host_decides`, `trial_of_two` |
| `secondTie` | `no_elimination`, `random`, `host_decides` |
| `afk` | `abstain`, `host_assigns` |
| `voteReveal` | `sequential`, `all_at_once` |
| `endgameVeil` | `final_4`, `final_5`, `final_6`, `off` |

---

## 5. Twist catalog (`catalogVersion` 1)

Fixed set. Each entry is self-contained: an id, params with defaults, and the phases
its logic hooks. The reducer has a `TwistRegistry` keyed by id; a config may only
reference ids in the registry for its `catalogVersion`.

| id | Name | What it does | Params (defaults) | Hooks |
|---|---|---|---|---|
| `hidden_legacy` | Hidden Legacy | If the last **original** Traitor is eliminated before the trigger, the app secretly converts one living Faithful to a Recruited Traitor; only host + recruit are told. Revealed at Results. | `trigger`: `before_round_3` \| `while_players_above_5` \| `{beforeRound:int}` (= `before_round_3`) | WinCheck, RoleState, Results |
| `poisoned_gift` | Poisoned Gift & the Shield | Per use, Traitors pick **Direct Poison** (a Faithful learns they're poisoned, plays one more discussion+vote, dies next sunrise) or **Claim the Shield** (public mystery item; a living player may claim before voting — True Shield blocks the next murder, Poisoned Shield poisons the holder). | `uses` (1), `announceClaim` (true), `hideClaimant` (true) | Night, MorningReveal, Elimination |
| `secret_accusation` | Secret Accusation | One Faithful holds a one-use public accusation. If spent, the accused gets `defense` seconds to answer before the vote. | `defenseSeconds` (60) | RoundTable, Vote |
| `blackmail` | Blackmail | One Faithful privately learns one **random** player's true alignment, and may share, hide, or lie about it. | — | RoleReveal |
| `double_agent` | Double Agent | One Faithful is flagged recruitable. Traitors may recruit them on a later night; otherwise they stay Faithful. | — | Night, RoleState |
| `last_will` | Last Will | An eliminated player may leave one host-approved final sentence — no private app info. | `maxChars` (140) | MorningReveal, Elimination |
| `confessional` | Confessional | Once per round, every living player privately submits one sentence; the host reveals them anonymously during discussion. | `perRound` (1) | RoundTable |
| `immunity_coin` | Immunity Coin | A challenge winner holds a **public** one-use immunity from elimination, spent whenever they choose. | — | Elimination |
| `silent_witness` | Silent Witness | One Faithful learns that a murdered player was **definitely Faithful** — and nothing about any Traitor. | — | MorningReveal |
| `false_reveal` | False Reveal | Once per game, the Traitors may force one eliminated Faithful's role to be announced as **unknown**. | `uses` (1) | MorningReveal, Elimination |
| `trial_of_two` | Trial of Two | On a tie, the two tied players each get `defense` seconds to speak while everyone else is muted, then a final vote. (Also selectable directly as `tieBreak`.) | `defenseSeconds` (45) | Vote (tie) |
| `survivors_choice` | Survivors' Choice | At the final four, the group may vote to end the game early. Any Traitor still alive → Traitors win. | — | WinCheck |

**Compatibility rules** (validated at lobby, enforced at `GAME_START`):

- `trial_of_two` twist + `tieBreak: "trial_of_two"` is redundant, not an error — the twist wins.
- `secret_accusation` and `double_agent`/`blackmail` all consume a "special Faithful"
  slot; the validator warns if enabled twists need more special Faithful than there are
  Faithful minus 1.
- `hidden_legacy` is incompatible with `endgameVeil: "off"` only in that Results must
  still reveal the recruitment moment — no block, just a note.
- `nightKill.doubleAfterRound` with `openingNight: "off"` shifts the round count by one
  (first real night is round 2).

---

## 6. The five shipped modes, as config

Each is a full `GameConfig` seeded with `scope = builtin`. Deltas from the defaults in §3 shown.

### Classic Conspiracy — `classic_conspiracy`
```json5
{ "preset": "classic_conspiracy",
  "table": { "minPlayers": 6, "maxPlayers": 10, "traitorCurve": [[6, 2]] },
  "nightKill": { "openingNight": "on", "doubleAfterRound": null, "allowSkip": false },
  "revealOnElimination": "always",
  "tieBreak": "revote", "secondTie": "no_elimination",
  "endgameVeil": "final_4",
  "twists": {} }
```

### Midnight Heist — `midnight_heist`
```json5
{ "preset": "midnight_heist",
  "table": { "minPlayers": 7, "maxPlayers": 12, "traitorCurve": [[7, 2], [10, 3]] },
  "revealOnElimination": "always",
  "tieBreak": "host_decides",
  "endgameVeil": "final_5",
  "twists": { "poisoned_gift": { "uses": 1, "announceClaim": true, "hideClaimant": true },
              "immunity_coin": {} } }
```

### Blood Moon — `blood_moon`
```json5
{ "preset": "blood_moon",
  "table": { "minPlayers": 8, "maxPlayers": 14, "traitorCurve": [[8, 3]] },
  "nightKill": { "openingNight": "on", "doubleAfterRound": 2, "allowSkip": true },
  "revealOnElimination": "always",
  "tieBreak": "random",
  "endgameVeil": "final_5",
  "twists": {} }
```

### The Last Alibi — `the_last_alibi`
```json5
{ "preset": "the_last_alibi",
  "table": { "minPlayers": 9, "maxPlayers": 16, "traitorCurve": [[9, 3], [13, 4]] },
  "nightKill": { "openingNight": "on", "requireTraitorConsensus": true },
  "revealOnElimination": "alternating",
  "tieBreak": "sudden_death", "suddenDeathSeconds": 30,
  "endgameVeil": "final_6",
  "twists": {} }
```

### Final Gambit — `final_gambit`
```json5
{ "preset": "final_gambit",
  "table": { "minPlayers": 5, "maxPlayers": 8, "traitorCurve": [[5, 1], [7, 2]] },
  "nightKill": { "openingNight": "off" },
  "revealOnElimination": "always",
  "tieBreak": "no_elimination",
  "endgameVeil": "final_4",
  "twists": { "secret_accusation": { "defenseSeconds": 60 } } }
```

---

## 7. Storage — `game_config_preset`

```sql
CREATE TABLE game_config_preset (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scope           TEXT NOT NULL,            -- 'builtin' | 'group' | 'user'
    owner_group_id  UUID REFERENCES groups (id) ON DELETE CASCADE,   -- scope='group'
    owner_user_id   UUID REFERENCES users  (id) ON DELETE CASCADE,   -- scope='user'
    slug            TEXT,                     -- 'blood_moon' etc. for builtins; null otherwise
    name            TEXT NOT NULL,
    description     TEXT,
    config          JSONB NOT NULL,
    catalog_version INT  NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (scope, slug)                      -- one builtin per slug
);
```

- Builtins seeded by a Flyway migration + a `data.sql` (or a `@PostConstruct` seeder
  guarded by `scope='builtin'` upsert on `slug`).
- `game_sessions` gains `config JSONB NOT NULL` + `config_preset_id UUID NULL` (the
  preset this session started from, for stats like "Blood Moon win rate").

---

## 8. Validation

Run at lobby (live, non-blocking warnings) and again at `GAME_START` (blocking):

1. `table.players` within `[minPlayers, maxPlayers]` **unless** `adminOverride` — then
   `[4, 20]` and the host must have accepted the balance warning.
2. Resolved traitor count `≥ 1` and `≤ floor(players / 2) - 1`.
3. Every `twists` key exists in the `TwistRegistry` for `catalogVersion`.
4. Special-Faithful budget (see §5 compatibility rules).
5. `timers` within their documented ranges.
6. `endgameVeil` threshold `< table.players` (else it's on from the start — allowed,
   but warn).
