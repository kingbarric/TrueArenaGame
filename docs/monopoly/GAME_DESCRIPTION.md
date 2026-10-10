# PlayHuud Monopoly — game description and implementation contract

**Documented before implementation · 10 October 2026**

## The game

**Monopoly is a property trading game inside an existing Huud.** Players travel around a shared board, buy property, collect rent, negotiate trades and build an estate. **The last solvent player wins.** The bank and rules run on the server; being the Huud admin gives no advantage over other players.

**The approved visual reference is [the classic board with depth](classic-depth-concept-v1.png).** Use its wooden base, green felt, cream raised tiles, metallic pieces, small buildings, warm light and maroon controls. The playable board must have the correct spaces and property values; the concept image's North Avenue and prices are illustrative.

## V1 rules and deliberate digital choices

**Classic US board, 40 spaces, 2–8 players.** Match the familiar property groups, four railroads, two utilities and special spaces. Use **$1,500 starting cash**, **$200 for passing GO**, two server-generated dice, doubles and jail. **Free Parking pays nothing.** **Income Tax is a fixed $200 and Luxury Tax $100** for this implementation; do not mix historic tax alternatives into the UI. Capacity comes from the game configuration.

**Buy or auction:** an unowned property offers its printed purchase price. Declining opens an auction to every solvent player, including the player who declined. Online bidding proceeds around the roster: **raise the highest bid or pass**; passing withdraws from that auction. The bank assigns the property once bidding closes. **Rent is collected automatically**, with group ownership, railroads, utilities, mortgages and buildings taken into account. These are digital interaction choices built on the classic game loop. [Official classic game reference](https://instructions.hasbro.com/en-nz/instruction/monopoly-classic-game), [official movement and purchase rules](https://www.hasbro.com/common/instruct/monins.pdf).

**Buildings and finance:** complete colour groups unlock even building. Four houses can be exchanged for a hotel. The bank has **32 houses and 12 hotels**. Sell buildings evenly for half their cost. A property group's buildings must be sold before any property in it can be mortgaged or traded. Mortgages disable rent on that property; lifting a mortgage costs its principal plus **10%**. The digital bank serializes building purchases; shortages block purchases until stock returns. **Simultaneous building-stock auctions are outside this first version.** [Official building and mortgage reference](https://www.hasbro.com/common/instruct/Monopoly_Vintage.pdf).

**Trade:** players can privately offer cash and unimproved deeds. The recipient must accept; ownership and balances are revalidated together when the offer is accepted. Mortgaged deeds carry their mortgage and the recipient's immediate interest payment. **No player-to-player loans.** Pending offers remain private; completed trades are public. Jail cards can be used by their holder; trading jail cards is a later extension.

**Jail and cards:** three consecutive doubles, Go to Jail or a card can send a player to jail without a GO salary. On their turns a jailed player may pay $50, use a held jail card or try doubles. A failed third attempt requires payment before movement. Doubles used to escape jail do not grant another roll. Chance and Community Chest resolve movement, payments, repairs, jail and held release cards; their shuffled order stays private. Card wording uses concise original descriptions of effects.

**Debt and bankruptcy:** owing more than available cash opens a debt decision, rather than immediately eliminating the player. They can sell buildings, mortgage deeds or negotiate a trade, then pay. Bankruptcy ends their participation and resolves assets to the creditor or bank. Bank-held deeds are auctioned. **Bankruptcy must follow a real unpaid obligation; a temporary disconnect alone never bankrupts a player.** Mortgage interest and bankruptcy transfers follow the financial rules above. [Official financial and bankruptcy reference](https://www.hasbro.com/common/instruct/Monopoly-Sorry_Plus_6_Classic_Games_%28item_41596%29.pdf).

## Starting and finishing inside the Huud

1. **Join Huud:** a viewer asks to join; admission supplies the existing Huud mic permission.
2. **Choose Monopoly:** the admin selects the game. Participants request to play separately.
3. **Select players:** the admin checks the roster; the admin may play or watch.
4. **Start:** lock the roster, allocate distinct tokens and start the server-controlled match. The first implementation assigns tokens and the opening turn by roster order.
5. **Play:** Huud voice and chat remain available. Players have mic access by default. Viewers receive a spectator-safe board.
6. **Results:** display the winner and each player's estate. **The Huud continues** with its audience, voice and chat; the admin can organize a rematch or another game.

**Only the permanent Huud owner can end Live.** Browsing elsewhere and host absence do not end a running match. The existing **24-hour confirmed inactivity** policy applies; an active participant, viewer, game connection or voice connection keeps the Huud open.

## The screen

**Bold, readable items are required:** thick property bands and outlines, distinct ownership colours, large token silhouettes, clear houses/hotels, prominent cash balances and heavy-weight labels. Tokens sharing a square must remain individually visible. The board can zoom and pan; tapping a tiny property opens a large deed card.

**One main portrait screen:** Huud header → player strip → raised classic board → current decision → **chat box at the bottom**. The chat box shows the latest Huud messages, a text field and a Send button. It is visibly present during play, not only an icon hidden in a menu. Participants can write; spectators follow the Huud's existing chat permissions. Expand it for history. The keyboard must not cover the composer or current action.

**Turn controls change with the situation:** Roll Dice, Buy/Auction, Bid/Pass, Pay Debt or End Turn. Properties and Trade open sheets. A player never sees active controls for another player's decision. Spectators see the same public board with a watch-only status.

**Depth stays practical:** layered board artwork, beveled tiles, realistic token shading and contact shadows create the approved depth. Keep the large decision labels horizontal/readable and animate only the changing pieces. Respect reduced motion; do not make camera effects essential to understanding a move.

## Authority, network behaviour and verification

**Server-authoritative:** validate player eligibility, turn, phase, funds, ownership, stock and each action's unique ID. A client cannot choose dice, supply money or move another token. Reject invalid actions without changing state.

**Separate public and private state:** publish positions, cash, deeds, buildings, current dice, auction state and resolved events. Hide future random outcomes, deck order and pending trade offers from other players and spectators. Publish a player's private offers only to that player.

**Reconnection:** the transport retrieves the authoritative snapshot, including the current decision, when a player reconnects. A decision allows **180 seconds** before a conservative server action keeps the match moving: roll, auction an unpurchased deed, pass an auction bid, or end the turn. For an unpaid debt, automatic building sales and mortgages attempt payment first; insolvency is resolved only if that real debt cannot be covered. These timeouts are digital rules and are shown in the match.

**Required checks:** purchases and auctions; correct rents; doubles and jail; stock/even building; mortgages and trades; debt and bankruptcy; action idempotency; private spectator payloads; reconnect snapshots; full Huud roster/voice/chat integration; narrow phone layouts and visible chat while playing.

**Implementation lives on `codex/monopoly-classic-depth`, isolated from SlayHuud and the other game branches.**
