package app.truearena.game.monopoly;

import app.truearena.engine.*;
import app.truearena.game.monopoly.MonopolyBoard.Space;
import app.truearena.game.monopoly.MonopolyState.*;
import java.util.*;

/**
 * Pure, authoritative classic rules. No future roll, deck order or private offer enters the
 * broadcast.
 */
public final class MonopolyModule implements GameModule {
  @Override
  public String gameType() {
    return "monopoly";
  }

  @Override
  public boolean hasPrivatePlayerState() {
    return true;
  }

  @Override
  public List<Phase> definePhases(GameSettings config) {
    int seconds = ((MonopolyConfig) config).decisionSeconds();
    return List.of(
        new Phase("Roll", seconds),
        new Phase("Purchase", seconds),
        new Phase("Auction", seconds),
        new Phase("Manage", seconds),
        new Phase("Debt", seconds),
        Phase.untimed("Results"));
  }

  @Override
  public GameState initialState(List<String> ids, GameSettings config, RandomSource rng) {
    require(
        ids.size() >= MonopolyConfig.MIN_PLAYERS
            && ids.size() <= MonopolyConfig.MAX_PLAYERS
            && new HashSet<>(ids).size() == ids.size()
            && ids.stream().allMatch(id -> id != null && !id.isBlank()),
        "ROSTER",
        "Monopoly needs 2–8 different players");
    Data d = new Data();
    d.config = (MonopolyConfig) config;
    d.seed = rng.seed();
    d.players.addAll(ids);
    for (String id : ids) d.people.put(id, new Player(1500, 0, false, 0, false, List.of()));
    for (Space s : MonopolyBoard.SPACES)
      if (s.buyable()) d.deeds.put(s.id(), new Deed(null, 0, false));
    for (int i = 0; i < 16; i++) {
      d.chance.add(i);
      d.chest.add(i);
    }
    rng.shuffle(d.chance);
    rng.shuffle(d.chest);
    event(d, "GAME_STARTED", Map.of("players", List.copyOf(ids)));
    return new MonopolyState(d);
  }

  @Override
  public GameState onPlayerAction(GameState state, PlayerAction a) {
    Data d = ((MonopolyState) state).copy();
    if (d.actionIds.contains(a.actionId())) return state;
    require(d.winner == null, "FINISHED", "This match has ended");
    require(
        d.people.containsKey(a.actor()) && !d.people.get(a.actor()).bankrupt(),
        "PLAYER",
        "Only active players can act");
    String actor = a.actor(), beforeActor = actor(d);
    String beforePhase = d.phase;
    switch (a.type()) {
      case "ROLL" -> {
        turn(d, actor, "Roll");
        roll(d);
      }
      case "BUY" -> {
        turn(d, actor, "Purchase");
        Space s = MonopolyBoard.at(d.people.get(actor).position());
        spend(d, actor, s.price());
        d.deeds.put(s.id(), new Deed(actor, 0, false));
        event(
            d, "PROPERTY_BOUGHT", Map.of("player", actor, "property", s.id(), "amount", s.price()));
        manage(d);
      }
      case "AUCTION" -> {
        turn(d, actor, "Purchase");
        auction(d, d.people.get(actor).position(), "Manage");
      }
      case "BID" -> bid(d, actor, number(a, "amount", 1, 1_000_000));
      case "PASS" -> pass(d, actor);
      case "END_TURN" -> {
        turn(d, actor, "Manage");
        end(d);
      }
      case "BUILD" -> build(d, actor, property(a));
      case "SELL_BUILDING" -> sell(d, actor, property(a));
      case "SELL_GROUP" -> sellGroup(d, actor, property(a));
      case "MORTGAGE" -> mortgage(d, actor, property(a));
      case "UNMORTGAGE" -> {
        assetWindow(d, actor);
        int id = property(a);
        Deed p = owned(d, actor, id);
        require(p.mortgaged(), "MORTGAGE", "This deed is not mortgaged");
        int amount = redemption(id);
        spend(d, actor, amount);
        d.deeds.put(id, new Deed(actor, 0, false));
        event(d, "UNMORTGAGED", Map.of("player", actor, "property", id, "amount", amount));
      }
      case "PAY_DEBT" -> {
        require(
            "Debt".equals(d.phase) && actor.equals(d.bills.getFirst().debtor()),
            "TURN",
            "This is not your debt");
        settle(d);
      }
      case "BANKRUPT" -> {
        require(
            "Debt".equals(d.phase) && actor.equals(d.bills.getFirst().debtor()),
            "TURN",
            "This is not your debt");
        require(
            liquidWorth(d, actor) < d.bills.getFirst().amount(),
            "SOLVENT",
            "You can still pay by selling buildings or mortgaging deeds");
        bankrupt(d, actor, d.bills.getFirst().creditor());
        settle(d);
      }
      case "PAY_JAIL" -> {
        turn(d, actor, "Roll");
        Player p = d.people.get(actor);
        require(p.jailed(), "JAIL", "You are not in jail");
        spend(d, actor, 50);
        release(d, actor);
        event(d, "JAIL_RELEASED", Map.of("player", actor));
      }
      case "USE_JAIL_CARD" -> {
        turn(d, actor, "Roll");
        Player p = d.people.get(actor);
        require(p.jailed() && !p.jailCards().isEmpty(), "JAIL_CARD", "No jail card is available");
        List<String> cards = new ArrayList<>(p.jailCards());
        String deck = cards.removeFirst();
        returnJailCard(d, deck);
        d.people.put(actor, new Player(p.cash(), p.position(), false, 0, false, cards));
        event(d, "JAIL_RELEASED", Map.of("player", actor));
      }
      case "OFFER_TRADE" -> offer(d, a);
      case "ACCEPT_TRADE" -> accept(d, a);
      case "DECLINE_TRADE", "CANCEL_TRADE" -> {
        Trade t = findTrade(d, a.str("tradeId"));
        require(
            actor.equals(a.type().equals("CANCEL_TRADE") ? t.from() : t.to()),
            "TRADE",
            "That is not your offer");
        d.trades.remove(t);
        privateEvent(d, "TRADE_CLOSED", Map.of("id", t.id()), t.from(), t.to());
      }

      default -> throw new RuleViolation("ACTION", "Unknown Monopoly action");
    }
    d.actionIds.add(a.actionId());
    // Other players' trades/property management must not indefinitely reset the decision clock.
    if (actor.equals(beforeActor)
        || !Objects.equals(beforeActor, actor(d))
        || !beforePhase.equals(d.phase)) d.revision++;
    return new MonopolyState(d);
  }

  private static void require(boolean ok, String code, String message) {
    if (!ok) throw new RuleViolation(code, message);
  }

  private static int number(PlayerAction a, String key, int min, int max) {
    Object raw = a.data().get(key);
    require(raw instanceof Number, "NUMBER", "Enter a whole number for " + key);
    double value = ((Number) raw).doubleValue();
    require(
        Double.isFinite(value) && value == Math.rint(value) && value >= min && value <= max,
        "NUMBER",
        "Invalid " + key);
    return (int) value;
  }

  private static int property(PlayerAction a) {
    int id = number(a, "property", 0, 39);
    require(MonopolyBoard.at(id).buyable(), "PROPERTY", "This space has no deed");
    return id;
  }

  private static void turn(Data d, String actor, String phase) {
    require(d.phase.equals(phase) && d.turn().equals(actor), "TURN", "Wait for your turn");
  }

  private static void assetWindow(Data d, String actor) {
    require(
        Set.of("Roll", "Manage", "Debt").contains(d.phase),
        "PHASE",
        "Finish the current decision first");
    require(
        !"Debt".equals(d.phase) || actor.equals(d.bills.getFirst().debtor()),
        "DEBT",
        "The debtor must resolve their payment first");
  }

  private static Deed owned(Data d, String actor, int id) {
    Deed p = d.deeds.get(id);
    require(p != null && actor.equals(p.owner()), "OWNER", "You do not own that deed");
    return p;
  }

  private static void cash(Data d, String player, int amount) {
    Player p = d.people.get(player);
    d.people.put(player, p.cash(p.cash() + amount));
  }

  private static void spend(Data d, String player, int amount) {
    require(d.people.get(player).cash() >= amount, "CASH", "Not enough cash");
    cash(d, player, -amount);
  }

  private static void event(Data d, String type, Map<String, Object> payload) {
    d.events.add(GameEvent.pub(d.events.size() + 1L, type, payload));
  }

  private static void privateEvent(
      Data d, String type, Map<String, Object> payload, String... players) {
    for (String id : players)
      d.events.add(GameEvent.toPlayer(d.events.size() + 1L, type, payload, id));
  }

  private static String actor(Data d) {
    if (d.winner != null) return null;
    if (d.auction != null) return d.auction.actor();
    if (d.phase.equals("Debt") && !d.bills.isEmpty()) return d.bills.getFirst().debtor();
    return d.turn();
  }

  private static List<Integer> dice(Data d) {
    SplittableRandom rng = new SplittableRandom(d.seed ^ (0x9E3779B97F4A7C15L * (++d.rollCount)));
    return List.of(rng.nextInt(1, 7), rng.nextInt(1, 7));
  }

  private static void roll(Data d) {
    d.lastPayment = null;
    d.drawnCard = null;
    d.dice = dice(d);
    int total = d.dice.get(0) + d.dice.get(1);
    boolean doubleRoll = d.dice.get(0).equals(d.dice.get(1));
    String who = d.turn();
    Player p = d.people.get(who);
    event(d, "DICE_ROLLED", Map.of("player", who, "dice", d.dice));
    if (p.jailed()) {
      d.rollAgain = false;
      d.doubles = 0;
      if (doubleRoll) {
        release(d, who);
        move(d, total);
      } else if (p.jailTurns() < 2) {
        d.people.put(who, new Player(p.cash(), 10, true, p.jailTurns() + 1, false, p.jailCards()));
        manage(d);
        d.message = "Still in jail — try again next turn";
      } else {
        d.resume = "JailMove";
        d.bills.add(new Bill(who, null, 50, "Third jail turn"));
        settle(d);
      }
      return;
    }
    d.doubles = doubleRoll ? d.doubles + 1 : 0;
    d.rollAgain = doubleRoll;
    if (d.doubles == 3) {
      jail(d);
      manage(d);
      return;
    }
    move(d, total);
  }

  private static void release(Data d, String who) {
    Player p = d.people.get(who);
    d.people.put(who, new Player(p.cash(), p.position(), false, 0, p.bankrupt(), p.jailCards()));
  }

  private static void jail(Data d) {
    Player p = d.people.get(d.turn());
    d.people.put(d.turn(), new Player(p.cash(), 10, true, 0, false, p.jailCards()));
    d.rollAgain = false;
    d.doubles = 0;
    event(d, "SENT_TO_JAIL", Map.of("player", d.turn()));
    d.message = "Go to jail";
  }

  private static void move(Data d, int count) {
    Player p = d.people.get(d.turn());
    int destination = Math.floorMod(p.position() + count, 40);
    if (count > 0 && p.position() + count >= 40) {
      cash(d, d.turn(), 200);
      event(d, "PASSED_GO", Map.of("player", d.turn(), "amount", 200));
    }
    d.people.put(d.turn(), d.people.get(d.turn()).move(destination));
    land(d, 1, 0);
  }

  private static void advance(Data d, int destination, int rentMultiplier) {
    int old = d.people.get(d.turn()).position();
    if (destination < old || destination == 0) {
      cash(d, d.turn(), 200);
      event(d, "PASSED_GO", Map.of("player", d.turn(), "amount", 200));
    }
    d.people.put(d.turn(), d.people.get(d.turn()).move(destination));
    land(d, rentMultiplier, 1);
  }

  private static void manage(Data d) {
    d.phase = "Manage";
    d.message =
        d.rollAgain
            ? "Doubles! Finish managing, then roll again"
            : "Manage your properties or end your turn";
  }

  private static void land(Data d, int rentMultiplier, int depth) {
    require(depth < 5, "CARD_LOOP", "Unexpected card loop");
    int id = d.people.get(d.turn()).position();
    Space s = MonopolyBoard.at(id);
    event(d, "LANDED", Map.of("player", d.turn(), "property", id));
    d.message = s.name();
    if (s.buyable()) {
      Deed deed = d.deeds.get(id);
      if (deed.owner() == null) {
        d.phase = "Purchase";
        return;
      }
      if (!deed.owner().equals(d.turn())
          && !deed.mortgaged()
          && !d.people.get(deed.owner()).bankrupt()) {
        int rent = rent(d, id);
        if (s.kind().equals("railroad")) rent *= rentMultiplier;
        if (s.kind().equals("utility") && rentMultiplier == 10) {
          List<Integer> r = dice(d);
          rent = (r.get(0) + r.get(1)) * 10;
          event(d, "UTILITY_ROLL", Map.of("dice", r, "amount", rent));
        }
        bill(d, new Bill(d.turn(), deed.owner(), rent, "Rent: " + s.name()), "Manage");
        return;
      }
    } else
      switch (s.kind()) {
        case "tax" -> {
          bill(d, new Bill(d.turn(), null, id == 4 ? 200 : 100, s.name()), "Manage");
          return;
        }
        case "goToJail" -> jail(d);
        case "chance", "chest" -> {
          draw(d, s.kind(), depth);
          return;
        }
        default -> {}
      }
    manage(d);
  }

  private static boolean complete(Data d, String owner, Space s) {
    return MonopolyBoard.group(s).stream().allMatch(x -> owner.equals(d.deeds.get(x.id()).owner()));
  }

  static int rent(Data d, int id) {
    Space s = MonopolyBoard.at(id);
    Deed p = d.deeds.get(id);
    if (p.owner() == null || p.mortgaged()) return 0;
    if (s.kind().equals("street"))
      return s.rents().get(p.buildings())
          * (p.buildings() == 0 && complete(d, p.owner(), s) ? 2 : 1);
    long count =
        MonopolyBoard.group(s).stream()
            .filter(x -> p.owner().equals(d.deeds.get(x.id()).owner()))
            .count();
    if (s.kind().equals("railroad")) return 25 << ((int) count - 1);
    return (count == 2 ? 10 : 4) * d.dice.stream().mapToInt(Integer::intValue).sum();
  }

  private static void bill(Data d, Bill bill, String resume) {
    d.bills.add(bill);
    d.resume = resume;
    settle(d);
  }

  private static void settle(Data d) {
    if (d.winner != null) return;
    while (!d.bills.isEmpty()) {
      Bill b = d.bills.getFirst();
      Player p = d.people.get(b.debtor());
      if (p.bankrupt()) {
        d.bills.removeFirst();
        continue;
      }
      if (p.cash() < b.amount()) {
        d.phase = "Debt";
        d.message = b.reason() + " — $" + b.amount() + " due";
        return;
      }
      spend(d, b.debtor(), b.amount());
      if (b.creditor() != null && !d.people.get(b.creditor()).bankrupt())
        cash(d, b.creditor(), b.amount());
      event(
          d,
          "PAYMENT",
          Map.of(
              "player",
              b.debtor(),
              "to",
              b.creditor() == null ? "bank" : b.creditor(),
              "amount",
              b.amount(),
              "reason",
              b.reason()));
      d.lastPayment = b;
      d.bills.removeFirst();
    }
    String resume = d.resume;
    d.resume = "Manage";
    if (!d.bankAuctions.isEmpty()) {
      auction(d, d.bankAuctions.removeFirst(), resume);
      return;
    }
    if (d.people.get(d.turn()).bankrupt() || resume.equals("Next")) {
      next(d);
      return;
    }
    if (resume.equals("JailMove")) {
      release(d, d.turn());
      move(d, d.dice.stream().mapToInt(Integer::intValue).sum());
      return;
    }
    manage(d);
  }

  private static void end(Data d) {
    d.trades.clear();
    if (d.rollAgain && !d.people.get(d.turn()).jailed()) {
      d.phase = "Roll";
      d.message = "Doubles — roll again";
      return;
    }
    next(d);
  }

  private static void next(Data d) {
    if (d.winner != null) return;
    for (int i = 0; i < d.players.size(); i++) {
      d.turnIndex = (d.turnIndex + 1) % d.players.size();
      if (!d.people.get(d.turn()).bankrupt()) break;
    }
    d.lastPayment = null;
    d.drawnCard = null;
    d.turnNumber++;
    d.doubles = 0;
    d.rollAgain = false;
    d.dice = List.of();
    d.phase = "Roll";
    d.message = "Roll the dice";
    d.trades.clear();
    event(d, "TURN_STARTED", Map.of("player", d.turn(), "turn", d.turnNumber));
  }

  private static void auction(Data d, int id, String resume) {
    List<String> eligible = d.players.stream().filter(x -> !d.people.get(x).bankrupt()).toList();
    d.auction = new Auction(id, 0, null, eligible, 0, resume);
    d.phase = "Auction";
    d.message = "Auction: " + MonopolyBoard.at(id).name();
    event(d, "AUCTION_STARTED", Map.of("property", id));
  }

  private static void bid(Data d, String actor, int amount) {
    Auction a = d.auction;
    require(a != null && actor.equals(a.actor()), "AUCTION_TURN", "Wait for your auction turn");
    require(
        amount > a.bid() && d.people.get(actor).cash() >= amount,
        "BID",
        "Bid above the current price using available cash");
    d.auction = new Auction(a.property(), amount, actor, a.eligible(), a.index(), a.resume());
    event(d, "AUCTION_BID", Map.of("player", actor, "amount", amount));
    auctionNext(d);
  }

  private static void pass(Data d, String actor) {
    Auction a = d.auction;
    require(a != null && actor.equals(a.actor()), "AUCTION_TURN", "Wait for your auction turn");
    List<String> eligible = new ArrayList<>(a.eligible());
    eligible.remove(actor);
    d.auction =
        new Auction(
            a.property(),
            a.bid(),
            a.bidder(),
            eligible,
            eligible.isEmpty() ? 0 : Math.floorMod(a.index() - 1, eligible.size()),
            a.resume());
    event(d, "AUCTION_PASSED", Map.of("player", actor));
    auctionNext(d);
  }

  private static void auctionNext(Data d) {
    Auction a = d.auction;
    if (a.eligible().isEmpty()
        || a.eligible().size() == 1
            && a.bidder() != null
            && a.eligible().getFirst().equals(a.bidder())) {
      if (a.bidder() != null) {
        spend(d, a.bidder(), a.bid());
        d.deeds.put(a.property(), new Deed(a.bidder(), 0, false));
      }
      event(
          d,
          "AUCTION_ENDED",
          Map.of(
              "property",
              a.property(),
              "player",
              a.bidder() == null ? "bank" : a.bidder(),
              "amount",
              a.bid()));
      d.auction = null;
      d.resume = a.resume();
      settle(d);
      return;
    }
    int index = a.index();
    do {
      index = (index + 1) % a.eligible().size();
    } while (a.eligible().get(index).equals(a.bidder()));
    d.auction = new Auction(a.property(), a.bid(), a.bidder(), a.eligible(), index, a.resume());
  }

  private static int houses(Data d) {
    return 32
        - d.deeds.values().stream().filter(p -> p.buildings() < 5).mapToInt(Deed::buildings).sum();
  }

  private static int hotels(Data d) {
    return 12 - (int) d.deeds.values().stream().filter(p -> p.buildings() == 5).count();
  }

  private static void build(Data d, String actor, int id) {
    assetWindow(d, actor);
    require(!d.phase.equals("Debt"), "DEBT", "Resolve your debt before building");
    Deed p = owned(d, actor, id);
    Space s = MonopolyBoard.at(id);
    require(
        s.kind().equals("street") && complete(d, actor, s),
        "GROUP",
        "Own the entire colour group to build");
    List<Space> group = MonopolyBoard.group(s);
    require(
        group.stream().noneMatch(x -> d.deeds.get(x.id()).mortgaged()),
        "MORTGAGE",
        "Redeem the group's mortgages before building");
    int min = group.stream().mapToInt(x -> d.deeds.get(x.id()).buildings()).min().orElse(0);
    require(
        p.buildings() == min && p.buildings() < 5,
        "EVEN_BUILD",
        "Build evenly across the colour group");
    require(
        p.buildings() == 4 ? hotels(d) > 0 : houses(d) > 0,
        "BANK_STOCK",
        "The bank has no available buildings");
    spend(d, actor, s.buildingCost());
    d.deeds.put(id, new Deed(actor, p.buildings() + 1, false));
    event(d, "BUILT", Map.of("player", actor, "property", id, "buildings", p.buildings() + 1));
  }

  private static void sell(Data d, String actor, int id) {
    assetWindow(d, actor);
    Deed p = owned(d, actor, id);
    Space s = MonopolyBoard.at(id);
    int max =
        MonopolyBoard.group(s).stream()
            .mapToInt(x -> d.deeds.get(x.id()).buildings())
            .max()
            .orElse(0);
    require(
        p.buildings() > 0 && p.buildings() == max,
        "EVEN_SELL",
        "Sell evenly across the colour group");
    require(
        p.buildings() != 5 || houses(d) >= 4,
        "BANK_STOCK",
        "Not enough replacement houses — sell the entire group's buildings instead");
    cash(d, actor, s.buildingCost() / 2);
    d.deeds.put(id, new Deed(actor, p.buildings() - 1, false));
    event(d, "BUILDING_SOLD", Map.of("player", actor, "property", id));
  }

  private static void sellGroup(Data d, String actor, int id) {
    assetWindow(d, actor);
    Space s = MonopolyBoard.at(id);
    owned(d, actor, id);
    require(
        s.kind().equals("street") && complete(d, actor, s),
        "GROUP",
        "You must own the colour group");
    int amount = 0;
    for (Space x : MonopolyBoard.group(s)) {
      Deed p = d.deeds.get(x.id());
      amount += p.buildings() * x.buildingCost() / 2;
      d.deeds.put(x.id(), new Deed(actor, 0, p.mortgaged()));
    }
    require(amount > 0, "BUILDINGS", "There are no buildings to sell");
    cash(d, actor, amount);
    event(d, "GROUP_SOLD", Map.of("player", actor, "group", s.group(), "amount", amount));
  }

  private static void mortgage(Data d, String actor, int id) {
    assetWindow(d, actor);
    Deed p = owned(d, actor, id);
    Space s = MonopolyBoard.at(id);
    require(!p.mortgaged(), "MORTGAGE", "Already mortgaged");
    require(
        MonopolyBoard.group(s).stream().noneMatch(x -> d.deeds.get(x.id()).buildings() > 0),
        "BUILDINGS",
        "Sell the colour group's buildings first");
    cash(d, actor, s.mortgage());
    d.deeds.put(id, new Deed(actor, 0, true));
    event(d, "MORTGAGED", Map.of("player", actor, "property", id, "amount", s.mortgage()));
  }

  private static int interest(int id) {
    return (MonopolyBoard.at(id).mortgage() + 9) / 10;
  }

  private static int redemption(int id) {
    return MonopolyBoard.at(id).mortgage() + interest(id);
  }

  private static int liquidWorth(Data d, String actor) {
    int value = d.people.get(actor).cash();
    for (var entry : d.deeds.entrySet())
      if (actor.equals(entry.getValue().owner())) {
        Space s = MonopolyBoard.at(entry.getKey());
        Deed p = entry.getValue();
        value += p.buildings() * s.buildingCost() / 2;
        if (!p.mortgaged()) value += s.mortgage();
      }
    return value;
  }

  private static void bankrupt(Data d, String actor, String creditor) {
    Player p = d.people.get(actor);
    if (p.bankrupt()) return;
    if (creditor != null && d.people.get(creditor).bankrupt()) creditor = null;
    int cash = p.cash(), fees = 0;
    for (var entry : new ArrayList<>(d.deeds.entrySet()))
      if (actor.equals(entry.getValue().owner())) {
        int id = entry.getKey();
        Deed deed = entry.getValue();
        cash += deed.buildings() * MonopolyBoard.at(id).buildingCost() / 2;
        if (creditor == null) {
          d.deeds.put(id, new Deed(null, 0, false));
          d.bankAuctions.add(id);
        } else {
          d.deeds.put(id, new Deed(creditor, 0, deed.mortgaged()));
          if (deed.mortgaged()) fees += interest(id);
        }
      }
    if (creditor != null) {
      cash(d, creditor, cash);
      Player c = d.people.get(creditor);
      List<String> cards = new ArrayList<>(c.jailCards());
      cards.addAll(p.jailCards());
      d.people.put(
          creditor, new Player(c.cash(), c.position(), c.jailed(), c.jailTurns(), false, cards));
    } else for (String deck : p.jailCards()) returnJailCard(d, deck);
    d.people.put(actor, new Player(0, p.position(), false, 0, true, List.of()));
    d.bills.removeIf(b -> b.debtor().equals(actor));
    if (fees > 0) d.bills.addFirst(new Bill(creditor, null, fees, "Mortgage transfer interest"));
    d.trades.removeIf(t -> t.from().equals(actor) || t.to().equals(actor));
    event(d, "BANKRUPT", Map.of("player", actor, "to", creditor == null ? "bank" : creditor));
    List<String> alive = d.players.stream().filter(x -> !d.people.get(x).bankrupt()).toList();
    if (alive.size() == 1) {
      d.winner = alive.getFirst();
      d.phase = "Results";
      d.auction = null;
      d.bills.clear();
      d.trades.clear();
      event(d, "GAME_ENDED", Map.of("winner", d.winner));
      return;
    }
    if (d.auction != null) {
      Auction a = d.auction;
      List<String> eligible = new ArrayList<>(a.eligible());
      eligible.remove(actor);
      String bidder = actor.equals(a.bidder()) ? null : a.bidder();
      int index = Math.min(a.index(), Math.max(0, eligible.size() - 1));
      d.auction =
          new Auction(
              a.property(), bidder == null ? 0 : a.bid(), bidder, eligible, index, a.resume());
      // Keep the current auction alive; queued bank deeds run afterwards.
      if (eligible.isEmpty() || eligible.size() == 1 && eligible.getFirst().equals(bidder))
        auctionNext(d);
      return;
    }
    if (actor.equals(d.turn())) d.resume = "Next";
  }

  private static List<Integer> deedList(PlayerAction a, String key) {
    Object raw = a.data().getOrDefault(key, List.of());
    require(raw instanceof List<?>, "TRADE", "Choose valid deeds");
    List<Integer> ids = new ArrayList<>();
    for (Object v : (List<?>) raw) {
      require(
          v instanceof Number
              && Double.isFinite(((Number) v).doubleValue())
              && ((Number) v).doubleValue() >= 0
              && ((Number) v).doubleValue() < 40
              && ((Number) v).doubleValue() == Math.rint(((Number) v).doubleValue()),
          "TRADE",
          "Invalid deed");
      int id = ((Number) v).intValue();
      require(id >= 0 && id < 40 && MonopolyBoard.at(id).buyable(), "TRADE", "Invalid deed");
      ids.add(id);
    }
    require(ids.size() == new HashSet<>(ids).size(), "TRADE", "A deed can only appear once");
    return ids;
  }

  private static void tradeDeeds(Data d, String owner, List<Integer> ids) {
    for (int id : ids) {
      owned(d, owner, id);
      require(
          MonopolyBoard.group(MonopolyBoard.at(id)).stream()
              .noneMatch(x -> d.deeds.get(x.id()).buildings() > 0),
          "TRADE_BUILDINGS",
          "Sell buildings in the group before trading");
    }
  }

  private static void validateTrade(Data d, Trade t) {
    require(
        !d.people.get(t.from()).bankrupt() && !d.people.get(t.to()).bankrupt(),
        "TRADE",
        "That player has left the game");
    tradeDeeds(d, t.from(), t.giveDeeds());
    tradeDeeds(d, t.to(), t.takeDeeds());
    int fromFees =
        t.takeDeeds().stream()
            .filter(id -> d.deeds.get(id).mortgaged())
            .mapToInt(MonopolyModule::interest)
            .sum();
    int toFees =
        t.giveDeeds().stream()
            .filter(id -> d.deeds.get(id).mortgaged())
            .mapToInt(MonopolyModule::interest)
            .sum();
    require(
        d.people.get(t.from()).cash() >= t.giveCash()
            && d.people.get(t.to()).cash() >= t.takeCash()
            && d.people.get(t.from()).cash() - t.giveCash() + t.takeCash() >= fromFees
            && d.people.get(t.to()).cash() - t.takeCash() + t.giveCash() >= toFees,
        "TRADE_CASH",
        "Both players need cash for the exchange and mortgage interest");
  }

  private static void offer(Data d, PlayerAction a) {
    assetWindow(d, a.actor());
    String to = a.str("to");
    require(
        to != null
            && !to.equals(a.actor())
            && d.people.containsKey(to)
            && !d.people.get(to).bankrupt(),
        "TRADE",
        "Choose another active player");
    Trade t =
        new Trade(
            a.actionId(),
            a.actor(),
            to,
            number(a, "giveCash", 0, 1_000_000),
            number(a, "takeCash", 0, 1_000_000),
            deedList(a, "giveDeeds"),
            deedList(a, "takeDeeds"));
    require(
        t.giveCash() + t.takeCash() > 0 || !t.giveDeeds().isEmpty() || !t.takeDeeds().isEmpty(),
        "TRADE",
        "Add cash or a deed");
    validateTrade(d, t);
    d.trades.removeIf(x -> x.from().equals(t.from()));
    d.trades.add(t);
    privateEvent(d, "TRADE_OFFER", Map.of("offer", t), t.from(), t.to());
  }

  private static Trade findTrade(Data d, String id) {
    return d.trades.stream()
        .filter(t -> t.id().equals(id))
        .findFirst()
        .orElseThrow(() -> new RuleViolation("TRADE", "That offer is no longer available"));
  }

  private static void accept(Data d, PlayerAction a) {
    require(
        Set.of("Roll", "Manage", "Debt").contains(d.phase),
        "PHASE",
        "Finish the current decision first");
    Trade t = findTrade(d, a.str("tradeId"));
    require(a.actor().equals(t.to()), "TRADE", "Only the recipient can accept");
    require(
        !d.phase.equals("Debt")
            || t.from().equals(d.bills.getFirst().debtor())
            || t.to().equals(d.bills.getFirst().debtor()),
        "DEBT",
        "Resolve the debt first");
    validateTrade(d, t);
    cash(d, t.from(), t.takeCash() - t.giveCash());
    cash(d, t.to(), t.giveCash() - t.takeCash());
    transfer(d, t.giveDeeds(), t.to());
    transfer(d, t.takeDeeds(), t.from());
    d.trades.clear();
    event(
        d,
        "TRADE_COMPLETED",
        Map.of(
            "from",
            t.from(),
            "to",
            t.to(),
            "giveCash",
            t.giveCash(),
            "takeCash",
            t.takeCash(),
            "giveDeeds",
            t.giveDeeds(),
            "takeDeeds",
            t.takeDeeds()));
  }

  private static void transfer(Data d, List<Integer> ids, String owner) {
    for (int id : ids) {
      Deed p = d.deeds.get(id);
      if (p.mortgaged()) spend(d, owner, interest(id));
      d.deeds.put(id, new Deed(owner, 0, p.mortgaged()));
    }
  }

  private static void returnJailCard(Data d, String deck) {
    (deck.equals("chance") ? d.chance : d.chest).add(deck.equals("chance") ? 9 : 4);
  }

  private static void draw(Data d, String deck, int depth) {
    List<Integer> cards = deck.equals("chance") ? d.chance : d.chest;
    int card = cards.removeFirst();
    boolean jailCard = card == (deck.equals("chance") ? 9 : 4);
    if (!jailCard) cards.add(card);
    String[] chance = {
      "Advance to GO",
      "Advance to Illinois Avenue",
      "Advance to St. Charles Place",
      "Advance to Boardwalk",
      "Take a trip to Reading Railroad",
      "Advance to the nearest railroad; pay double rent",
      "Advance to the nearest railroad; pay double rent",
      "Advance to the nearest utility; pay ten times a fresh dice roll",
      "Bank dividend: collect $50",
      "Keep this card to leave jail",
      "Go back three spaces",
      "Go directly to jail",
      "Repairs: $25 per house and $100 per hotel",
      "Speeding fine: pay $15",
      "Pay each other player $50",
      "Building loan: collect $150"
    };
    String[] chest = {
      "Advance to GO",
      "Bank error: collect $200",
      "Doctor's fee: pay $50",
      "Stock sale: collect $50",
      "Keep this card to leave jail",
      "Go directly to jail",
      "Holiday fund: collect $100",
      "Tax refund: collect $20",
      "Birthday: collect $10 from each player",
      "Life insurance: collect $100",
      "Hospital fee: pay $100",
      "School fee: pay $50",
      "Consultancy: collect $25",
      "Street repairs: $40 per house and $115 per hotel",
      "Beauty prize: collect $10",
      "Inheritance: collect $100"
    };
    String text = (deck.equals("chance") ? chance : chest)[card];
    d.message = text;
    d.drawnCard = text;
    event(d, "CARD_DRAWN", Map.of("deck", deck, "text", text));
    if (jailCard) {
      Player p = d.people.get(d.turn());
      List<String> held = new ArrayList<>(p.jailCards());
      held.add(deck);
      d.people.put(
          d.turn(), new Player(p.cash(), p.position(), p.jailed(), p.jailTurns(), false, held));
      manage(d);
      d.message = text;
      return;
    }
    if (deck.equals("chance"))
      switch (card) {
        case 0 -> {
          advance(d, 0, 1);
          return;
        }
        case 1 -> {
          advance(d, 24, 1);
          return;
        }
        case 2 -> {
          advance(d, 11, 1);
          return;
        }
        case 3 -> {
          advance(d, 39, 1);
          return;
        }
        case 4 -> {
          advance(d, 5, 1);
          return;
        }
        case 5, 6 -> {
          int pos = d.people.get(d.turn()).position();
          int dest =
              MonopolyBoard.SPACES.stream()
                  .filter(s -> s.kind().equals("railroad") && s.id() > pos)
                  .mapToInt(Space::id)
                  .min()
                  .orElse(5);
          advance(d, dest, 2);
          return;
        }
        case 7 -> {
          int pos = d.people.get(d.turn()).position();
          advance(d, pos < 12 ? 12 : pos < 28 ? 28 : 12, 10);
          return;
        }
        case 8 -> cash(d, d.turn(), 50);
        case 10 -> {
          Player p = d.people.get(d.turn());
          d.people.put(d.turn(), p.move(Math.floorMod(p.position() - 3, 40)));
          land(d, 1, depth + 1);
          return;
        }
        case 11 -> jail(d);
        case 12 -> {
          bill(d, new Bill(d.turn(), null, repairs(d, 25, 100), text), "Manage");
          return;
        }
        case 13 -> {
          bill(d, new Bill(d.turn(), null, 15, text), "Manage");
          return;
        }
        case 14 -> {
          for (String id : d.players)
            if (!id.equals(d.turn()) && !d.people.get(id).bankrupt())
              d.bills.add(new Bill(d.turn(), id, 50, text));
          d.resume = "Manage";
          settle(d);
          return;
        }
        case 15 -> cash(d, d.turn(), 150);
        default -> throw new IllegalStateException("Chance card");
      }
    else
      switch (card) {
        case 0 -> {
          advance(d, 0, 1);
          return;
        }
        case 1 -> cash(d, d.turn(), 200);
        case 2 -> {
          bill(d, new Bill(d.turn(), null, 50, text), "Manage");
          return;
        }
        case 3 -> cash(d, d.turn(), 50);
        case 5 -> jail(d);
        case 6, 9, 15 -> cash(d, d.turn(), 100);
        case 7 -> cash(d, d.turn(), 20);
        case 8 -> {
          for (String id : d.players)
            if (!id.equals(d.turn()) && !d.people.get(id).bankrupt())
              d.bills.add(new Bill(id, d.turn(), 10, text));
          d.resume = "Manage";
          settle(d);
          return;
        }
        case 10, 11 -> {
          bill(d, new Bill(d.turn(), null, card == 10 ? 100 : 50, text), "Manage");
          return;
        }
        case 12 -> cash(d, d.turn(), 25);
        case 13 -> {
          bill(d, new Bill(d.turn(), null, repairs(d, 40, 115), text), "Manage");
          return;
        }
        case 14 -> cash(d, d.turn(), 10);
        default -> throw new IllegalStateException("Chest card");
      }
    manage(d);
    d.message = text;
  }

  private static int repairs(Data d, int perHouse, int perHotel) {
    int total = 0;
    for (Deed p : d.deeds.values())
      if (d.turn().equals(p.owner()))
        total += p.buildings() == 5 ? perHotel : p.buildings() * perHouse;
    return total;
  }

  @Override
  public GameState onPhaseElapsed(GameState state, String phase) {
    Data d = ((MonopolyState) state).copy();
    if (d.winner != null || !d.phase.equals(phase)) return state;
    event(d, "DECISION_TIMED_OUT", Map.of("player", actor(d), "phase", phase));
    switch (phase) {
      case "Roll" -> roll(d);
      case "Purchase" -> auction(d, d.people.get(d.turn()).position(), "Manage");
      case "Auction" -> pass(d, d.auction.actor());
      case "Manage" -> end(d);
      case "Debt" -> {
        Bill debt = d.bills.getFirst();
        String who = debt.debtor();
        if (liquidWorth(d, who) < debt.amount()) bankrupt(d, who, debt.creditor());
        else {
          while (d.people.get(who).cash() < debt.amount()) {
            Integer built =
                d.deeds.entrySet().stream()
                    .filter(e -> who.equals(e.getValue().owner()) && e.getValue().buildings() > 0)
                    .max(Comparator.comparingInt(e -> e.getValue().buildings()))
                    .map(Map.Entry::getKey)
                    .orElse(null);
            if (built != null) {
              if (d.deeds.get(built).buildings() == 5 && houses(d) < 4) sellGroup(d, who, built);
              else sell(d, who, built);
            } else {
              int id =
                  d.deeds.entrySet().stream()
                      .filter(e -> who.equals(e.getValue().owner()) && !e.getValue().mortgaged())
                      .map(Map.Entry::getKey)
                      .findFirst()
                      .orElseThrow();
              mortgage(d, who, id);
            }
          }
        }
        settle(d);
      }
      default -> {
        return state;
      }
    }
    d.revision++;
    return new MonopolyState(d);
  }

  @Override
  public Set<String> playersToAct(GameState state) {
    String id = actor(((MonopolyState) state).copy());
    return id == null ? Set.of() : Set.of(id);
  }

  @Override
  public Optional<WinResult> checkWinCondition(GameState state) {
    Data d = ((MonopolyState) state).copy();
    if (d.winner == null) return Optional.empty();
    Map<String, String> outcomes = new LinkedHashMap<>();
    for (String id : d.players) outcomes.put(id, id.equals(d.winner) ? "won" : "lost");
    return Optional.of(new WinResult(d.winner, outcomes));
  }

  @Override
  public List<GameEvent> drainEvents(GameState before, GameState after) {
    return after.events().subList(before.events().size(), after.events().size());
  }

  @Override
  public PublicBroadcastState broadcastState(GameState state) {
    return new PublicBroadcastState(view(((MonopolyState) state).copy()));
  }

  @Override
  public PlayerVisibleState visibleStateFor(GameState state, String id) {
    Data d = ((MonopolyState) state).copy();
    Map<String, Object> view = view(d);
    if (d.people.containsKey(id))
      view.put(
          "tradeOffers",
          d.trades.stream().filter(t -> id.equals(t.from()) || id.equals(t.to())).toList());
    return new PlayerVisibleState(view);
  }

  private static Map<String, Object> view(Data d) {
    Map<String, Object> v = new LinkedHashMap<>();
    v.put("phase", d.phase);
    v.put("round", d.revision);
    v.put("players", d.players);
    v.put("playerState", d.people);
    v.put("deeds", d.deeds);
    v.put("board", MonopolyBoard.SPACES);
    v.put("turnPlayer", d.turn());
    v.put("decisionPlayer", actor(d));
    v.put("turnNumber", d.turnNumber);
    v.put("dice", d.dice);
    v.put("rollAgain", d.rollAgain);
    v.put("message", d.message);
    v.put("lastPayment", d.lastPayment);
    v.put("drawnCard", d.drawnCard);
    v.put("bankHouses", houses(d));
    v.put("bankHotels", hotels(d));
    v.put("auction", d.auction);
    v.put("debt", d.bills.isEmpty() ? null : d.bills.getFirst());
    v.put("winner", d.winner);
    return v;
  }
}
