# Traitors dynamics — agreed plan

Status: discussed 25–27 October 2026. Only the quieter round table is built, on `feature/traitors-dynamics`. Every other item here is a plan.

The five Traitors modes play too much alike. Apart from Midnight Heist's shield, a game is murder, talk, vote, repeat. This plan gives each mode a signature twist and lets the Traitors recruit when they lose people. It also gives two groups a part to play: players who are out of the game, and people watching.

## Already in the game

- **Table and reveals:** everyone sits around an oval round table, with the clock and the host's Skip in the middle. Murders and banishments are revealed at the table: 5 seconds, then the name, 3 seconds, then the role. A Traitor gets a celebration; a Faithful gets a sad reveal.
- **Music:** each scene has its own: night, round table, vote and reveal (eight Kevin MacLeod tracks, CC BY 4.0).
- **Ending:** the host can end the game for everyone. Nobody wins, and every role is shown.
- **Cyber Agents:** each has its own voice (sceptic, joker, detective, peacemaker, hothead, quiet). They use names and answer whoever spoke. A person always gets a reply.
- **Watching:** spectators see the real table read-only, and their reactions float up everyone's screen.
- **Quieter round table (on the branch):** the round-table music now plays at 7% instead of 22%, so people hear each other. Night, vote and reveal music stay at full level.

Twists each mode has today:

| Mode | Players | Today |
|---|---|---|
| Classic Conspiracy | 6–10 | Nothing — "pure deduction" |
| Midnight Heist | 7–12 | Poisoned Gift (the mystery shield is poisoned on a coin flip), Immunity Coin |
| Blood Moon | 8–14 | A double murder is possible from round 3 |
| The Last Alibi | 9–16 | Reveals alternate public, hidden, public; the Traitors must agree on a target |
| Final Gambit | 5–8 | No first-night murder; one Faithful holds a secret accusation |

`TwistRegistry` also has twists no built-in mode uses: Hidden Legacy, Double Agent, Blackmail, Silent Witness, Last Will, Confessional, False Reveal, Trial of Two and Survivors' Choice. Custom games can switch any of them on.

## Who gets what

| Mode | Signature twist | Also | Recruiting | Ghost Jury |
|---|---|---|---|---|
| **Classic Conspiracy** | Crime-Scene Clues | Crowd's Hunch | — | ✓ (after its revote) |
| **Midnight Heist** | The Poisoned Pie (replaces the coin-flip shield) | Immunity Coin, Crowd's Hunch | ✓ | ✓ |
| **Blood Moon** | The Black Spot | Double murder, Crowd's Hunch | ✓ | ✓ |
| **The Last Alibi** | Alibis | Crime-Scene Clues, Crowd's Hunch | ✓ | ✓ |
| **Final Gambit** | The Seer's Lantern | Last Stand, Secret Accusation, Crowd's Hunch | ✓ | ✓ |

Why: Classic stays power-free, so its clues are facts, not powers. Heist is about objects and gambles. Blood Moon is the dark one. The Last Alibi's large tables need more evidence to work with. Final Gambit is small and tense. In Custom games the host can switch every twist on or off.

## The twists

### 1. The Poisoned Pie — Midnight Heist

- **At night:** once a game, the Traitors bake a pie. They choose: a real shield or poison. It's their choice, no longer a coin flip.
- **In the morning:** the pie sits in the middle of the round table with one clue ("still warm — baked after midnight", "a faint smell of almonds"). The clue is true two times in three.
- **At the round table:** anyone alive can take it, first come first served. Traitors can take their own pie to look innocent.
- **Next morning:** a real shield glows gold and saves its holder from that night's murder. Poison makes the holder collapse in the morning reveal, as a delayed death.
- **Built from:** `poisoned_gift`, `CLAIM_SHIELD` and `poisonDue`. New: the Traitors' choice, the clue, and the pie on the table.

### 2. Crime-Scene Clues — Classic Conspiracy, The Last Alibi

- After each murder, one true but vague clue appears. It uses the seating, for example "a Traitor sat within two seats of the victim", and that part of the oval glows.
- The clue is always true but never names anyone. One clue per murder.
- Other kinds of clue to cycle through: "the killer has voted for a Faithful before", or "the killer spoke at the last round table".

### 3. Alibis — The Last Alibi

- **At night:** every living player secretly names who they were with.
- **In the morning:** the table shows the web of answers. Pairs who named each other show in gold; contradictions show in red ("Ada says Bola. Bola says Chidi.").
- **Traitors:** they have to coordinate their lies in their own chat. Faithful only know what they themselves said.

### 4. The Seer's Lantern — Final Gambit

- **The lantern:** one random Faithful secretly gets it. Once a game, at night, they see one player's true role.
- **The hunt:** the Traitors know a Seer exists but not who it is, so they hunt them. The Seer has to persuade the table without giving themselves away.

### 5. The Black Spot — Blood Moon

- **At night:** the Traitors mark a player with a cursed token.
- **At the round table:** whoever holds it must pass it to someone else, and you watch it travel round the oval. It can't go straight back to the person who passed it.
- **At the vote:** whoever holds it when voting opens loses their vote this round. Every pass is a public clue about who trusts whom.

### 6. The Crowd's Hunch — every mode (host can switch it off)

- **What it is:** the crowd secretly votes for who they think a Traitor is. At the round table, players see a live meter ("The crowd suspects Bola · 61%").
- **Who the crowd is:** spectators, plus **Faithful who are out of the game** (ghosts). Eliminated Traitors never vote. Spectators only see public information, so their vote is a real hunch, not a leak.
- **No spectators:** the ghosts are the crowd. **The meter shows only once at least 3 people have voted**, so no single vote can be traced back to its sender. Until then the meter reads "The crowd is still making up its mind" — or isn't shown at all on a round with no crowd yet.
- **Super Faithful** (see below) count double, and nobody is told this.

### 7. Last Stand — Final Gambit endgame

- At the final four, one Faithful can give up their place to reveal one player's role to everyone. It's a big gamble, once per game.

### 8. Recruiting — every mode except Classic Conspiracy

When the Traitors lose people, they can try to win Faithful over.

**How it works**

- **The offer:** on a recruiting night the Traitors pick a Faithful instead of murdering anyone. In the morning that Faithful privately sees: *"The Traitors want you. Join them — or else."*
- **Anonymous:** the offer doesn't say who the Traitors are, so refusing doesn't expose them.
- **Accept:** the player becomes a Traitor immediately and joins the Traitors' chat. If they're later eliminated, their role shows as "Traitor (recruited)".
- **Refuse:** they stay Faithful. The threat may be a **bluff**: next night the Traitors decide whether to murder them (the threat was real) or someone else. The refuser can tell the table they were approached, and nobody knows if they're telling the truth.
- **What the table sees:** the morning after a recruiting night says *"Nobody was murdered… but the Traitors were busy."*
- **Limits:** one offer a night, and nobody can be asked twice. No answer before the round table counts as a refusal.

**When they may recruit**

The Traitors win the moment they equal the Faithful in number. So after recruiting there must still be **at least two Faithful for every Traitor**, and the Traitors can never go **above their starting number**:

| Players alive | Most Traitors allowed |
|---|---|
| 12–14 | 4 |
| 9–11 | 3 |
| 6–8 | 2 |
| 5 or fewer | Recruiting closed |

- **Large tables:** with 3 Traitors, losing one while 9 or more are alive lets them recruit back to 3.
- **6–8 players:** losing one leaves 2, which is already the most allowed, so no recruit. If a second falls, they can recruit back to 2.
- **Result:** the Traitors keep at least 2 down to the last 6, then recruiting closes on its own.
- **Why not down to 5:** with 2 Traitors among 5 players, one wrong vote makes it 2 against 2 and the Traitors win on the spot.
- **If every Traitor is caught,** the Faithful win. No new Traitor appears, because catching them all is the Faithful's reward.

**Built from:** `RECRUITED_AS_TRAITOR`, `recruited_traitor` and `recruitDoubleAgent`. Hidden Legacy and Double Agent stay available for Custom games, but this rule replaces them in the built-in modes.

### 9. Super Faithful and the Ghost Jury — every mode

Faithful who are out of the game get a part to play.

- **Ghosts:** every eliminated Faithful, whether murdered or banished.
- **Super Faithful:** a ghost who voted for a real Traitor at least once while alive. They were right, and it cost them.

**The Ghost Jury settles ties**

- On a tie, before the mode's usual tie rule, the ghosts vote secretly between the tied players. **A Super Faithful's vote counts double.** The table only sees the verdict: *"The ghosts have spoken: Bola is banished."*
- **Nobody is told who is Super, not even the ghosts themselves.** Their extra weight is applied silently. Announcing it would reveal that someone they once voted for is a Traitor.
- **Where the rule applies:**
  - **Classic Conspiracy:** keeps its revote first; the Ghost Jury only settles a tie the revote doesn't break.
  - **Blood Moon** (random tie-break) and **Midnight Heist** (host decides): the Ghost Jury replaces those rules.
  - **The Last Alibi** and **Final Gambit:** the jury comes before their own tie rules.
- **Fallback:** with no ghosts yet, or if the jury itself ties, the mode's own rule decides.

**Their other voice**

Ghosts are part of the Crowd's Hunch, where Super Faithful count double, again without anyone being told.

**Ghosts never** talk at the table, send in the audience box or vote in the main vote. Their only voices are the jury and the hunch, so nothing they know can leak into the game.

## Cyber Agents

Every twist needs the agents to play it too:
- **Pie:** whether to grab it, and how much to trust the clue.
- **Black Spot:** who to pass it to.
- **Alibis:** who to name; Traitors lie in step.
- **Recruiting:** Traitors decide who to recruit and whether to carry out the threat. A Faithful accepts or refuses in its own style: a Hothead refuses loudly, a Quiet one might just accept.
- **Ghost Jury and Crowd's Hunch:** agent ghosts and spectators vote like everyone else.

## Build order

1. Recruiting (rules, the offer screen, the bluff, agents).
2. The Poisoned Pie.
3. Crime-Scene Clues.
4. Alibis.
5. Ghost Jury and Super Faithful.
6. Crowd's Hunch.
7. The Seer's Lantern, the Black Spot and Last Stand.

**For every twist:**
- **Server:** rules in `TrueArenaModule`, with tests that a spectator's view never contains a secret.
- **Table:** how it looks on the round table.
- **Agents:** the Cyber Agents taught to play it.
- **Balance:** a balance run of agent-only games per mode, aiming for the Traitors to win roughly 45–55%.

Build on `feature/traitors-dynamics`, test and commit, then ask before any install or deploy.

## Open questions

- How long does a Faithful have to answer a recruiting offer? Suggested: until the round table opens.
- Should the Pie's clue be true two times in three, or three times in four?
- Should Last Stand's reveal go to the whole table, or only to the Faithful who made the sacrifice?
- Should the Crowd's Hunch need 3 voters, or more for big tables?
