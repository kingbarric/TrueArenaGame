# Traitors dynamics — agreed plan

Status: discussed 25–27 October 2026; built on `feature/traitors-dynamics` on 27 October 2026 (see *As built* at the end). Not merged or deployed.

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

## As built

Everything above is built on `feature/traitors-dynamics`, with these choices and limits.

**Server** (`TrueArenaModule`, `TruearenaState`, `TwistRegistry`)
- **New twist ids:** `recruiting`, `poisoned_pie` (`uses`, `clueTruth` 0.67), `crime_clues`, `alibis`, `seer_lantern`, `black_spot`, `last_stand`, `crowd_hunch` (`minVoters` 3) and `ghost_jury` (`afterRevote` in Classic). Each mode's preset switches on its set from *Who gets what*.
- **New actions:**
  - recruiting: `RECRUIT_OFFER`, `RECRUIT_ANSWER`;
  - the pie: `BAKE_PIE`, `TAKE_PIE`;
  - alibis and the lantern: `ALIBI`, `SEER_LANTERN`;
  - the Black Spot: `PLACE_SPOT`, `PASS_SPOT`;
  - the endgame and the out: `LAST_STAND`, `GHOST_VOTE`, `CROWD_VOTE`.
- **A new phase, `GhostJury`,** runs for 30 seconds.
- **The night** ends early only once everyone it needs has acted: the Traitors (agreed, recruiting or skipping), every alibi, and the Seer's lantern. Otherwise the clock ends it.
- **The recruiting rule:**
  - It needs a lost Traitor, and the Traitors never go back above their starting number.
  - After a recruit, the number of Traitors must be at most a third of the living players, rounded down (players alive ÷ 3).
  - The offer is anonymous and replaces that night's murder.
  - No answer before the vote counts as a refusal, and nobody is asked twice.
- **Public versus private:**
  - The broadcast shows the pie (never its filling), the clues, the alibi board, the Black Spot, a Last Stand and the crowd meter.
  - Each player's own view adds their offer, their pie, their lantern visions, their jury seat and their own crowd vote.
  - The jury never publishes how many jurors it has, because that would reveal how many hidden-role eliminations were Faithful.
- **Spectators:** a spectator may send one game action, `CROWD_VOTE`, except in championship matches.

**Cyber Agents** (`TrueArenaBotAdapter`)
- **Twist moves:** each twist is a move an agent weighs once per phase.
  - The lead Traitor agent recruits (65%), bakes (60%, poison 55%) and places the Spot.
  - Every agent gives an alibi.
  - An offer is accepted by personality: Quiet 50%, Joker 35%, Peacemaker 25%, Detective 20%, Sceptic 15%, Hothead 5%. Hotheads and Sceptics announce a refusal at the table.
  - A shield-looking pie tempts 30% of agents; a poison-looking one, 8%.
  - The Seer lights the lantern (70%) and hints at a Traitor it saw.
  - Agent ghosts sit on the jury and join the crowd.
- **What agents learn from:** clues, alibis and visions feed their suspicion.
- **How agents vote:** they now weigh who the round table keeps naming.
- **Reading the table like people (every level):**
  - **The vote record:** voting out a revealed Faithful counts against you; voting out a revealed Traitor clears you. Once a Traitor is unmasked, whoever kept voting for the same names they did, round after round, comes under suspicion.
  - **Vouches:** agents remember who stood up for whom ("Leave Ada alone", "I trust Ada"). Vouching for someone later unmasked as a Traitor is damning; standing up for someone the agent already doubts is a small mark too.
  - **One name, not five:** when the table has settled on a name (named at least twice and clearly ahead), Faithful agents vote together on it unless their own evidence clears that player, and sometimes say so ("Let's not split the vote").
  - **Traitor slips:** a Traitor agent sometimes covers for a fellow Traitor who's being accused (35%), which the table can catch later. It goes after whoever keeps pointing at its side, and when the table has clearly settled on a fellow Traitor, it sometimes joins that vote to look clean (30%).
  - **Faithful vouch too:** a Faithful agent speaks up for someone its own evidence clears, so a vouch on its own proves nothing.

**App** (`traitors_twists.dart`, `game_screen.dart`, `table_ring.dart`)
- **At night:** the Traitors' plan chips; the lantern and alibi pickers.
- **The offer:** a sealed letter.
- **The tabletop tray:** pie, clue, Black Spot, alibis, lantern and Last Stand cards.
- **The seats:** clue glow, skull token, pie and vision badges.
- **The web:** "See the web" shows the alibi and Black Spot lines over a cleared table.
- **Elsewhere:** the crowd meter, the Ghost Jury stage, the silenced-vote screen, the Last Stand banner, and a feed line for every new event.

**The 2.5D table** (`table_depth.dart`, `table_ring.dart`, `traitors_reveal.dart`). The wood, the light and the camera have depth; names, votes, buttons, the tray and the web stay flat and readable.
- **The round table:** the top tilts away in true perspective (planks and grain foreshorten toward the far edge), the near edge shows the slab's thickness, and the table throws a shadow. The far row of seats sits a little closer together and smaller (90% at the top to 106% at the bottom), and every seat stands on a soft shadow.
- **Candlelight:** two candles on the far corners and a warm pool of light that flickers. The flicker steps about 12 times a second rather than every frame, to save battery. It stops when the screen is hidden or motion is reduced.
- **The reveals:** the oval table gets a rim and a shadow. During the drumroll the camera pushes in slowly (to 104%) and the edges darken; when the name comes up it leans toward that seat (to 108%). The morning reveal starts with the candles low and brings them up with the news. A Faithful lost dims them and turns the table cold; a Traitor caught leaves them bright.
- **The sealed letter:** it slides up from the table, turning straight and growing as it comes close enough to read.
- **Reduced motion:** the camera never moves, the flicker stops and the letter is simply there.

**Tests**
- `TraitorsDynamicsTest` (20): each twist, its limits and secrecy.
- `TraitorsAgentDynamicsTest` (9) and `TraitorsSpectatorTest`: agents and spectators.
- `traitors_dynamics_ui_test.dart` (12): the screens.
- `TraitorsBalanceSimulationTest`: 1,500 all-agent games, every mode playing to an end.
- `table_depth_test.dart` (6): the perspective maths, seat depth, the reveal camera, reduced motion and the letter.

**What balance testing can and can't tell us yet.** At first, all-agent games went to the Traitors 85–99% of the time in every mode. The agent Faithful were guessing and spreading their votes, while the Traitors always voted together. A simple model with no AI at all, using the real table sizes, reproduced those numbers.

Once agents read the vote record, remembered vouches and rallied behind one name, the Traitors' win rate fell to about 57–74% (one run: Classic 63%, Heist 62%, Blood Moon 69%, The Last Alibi 57%, Final Gambit 74%). Runs vary by a few points. Agents still can't read people, so this is a floor for the Faithful, not the game's balance.

The simulation shows which way a twist pushes:
- Crime-Scene Clues help the Faithful in Classic.
- The Seer moved Final Gambit within a few points.
- Recruiting nudges the Traitors up.
- Heist and Blood Moon (3 Traitors in 10) are the modes to watch once real games come in.

Real balance has to come from real tables. The next step is to read the Traitors win rate per mode from finished games on the test server, then tune `clueTruth`, the recruiting cap and the pie odds.

