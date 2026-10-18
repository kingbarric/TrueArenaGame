package app.truearena.game.monopoly;

import app.truearena.engine.*;
import java.util.*;

/** A frozen snapshot; transitions operate on an isolated copy. */
public final class MonopolyState implements GameState {
  public record Player(
      int cash,
      int position,
      boolean jailed,
      int jailTurns,
      boolean bankrupt,
      List<String> jailCards) {
    public Player {
      jailCards = List.copyOf(jailCards);
    }

    Player cash(int value) {
      return new Player(value, position, jailed, jailTurns, bankrupt, jailCards);
    }

    Player move(int value) {
      return new Player(cash, value, jailed, jailTurns, bankrupt, jailCards);
    }
  }

  public record Deed(String owner, int buildings, boolean mortgaged) {}

  public record Bill(String debtor, String creditor, int amount, String reason) {}

  public record Auction(
      int property, int bid, String bidder, List<String> eligible, int index, String resume) {
    public Auction {
      eligible = List.copyOf(eligible);
    }

    public String actor() {
      return eligible.isEmpty() ? null : eligible.get(index);
    }
  }

  public record Trade(
      String id,
      String from,
      String to,
      int giveCash,
      int takeCash,
      List<Integer> giveDeeds,
      List<Integer> takeDeeds) {
    public Trade {
      giveDeeds = List.copyOf(giveDeeds);
      takeDeeds = List.copyOf(takeDeeds);
    }
  }

  static final class Data {
    MonopolyConfig config;
    long seed;
    int rollCount, revision = 1, turnIndex, turnNumber = 1, doubles;
    String phase = "Roll", message = "Roll the dice", winner, resume = "Manage";
    List<String> players = new ArrayList<>();
    Map<String, Player> people = new LinkedHashMap<>();
    Map<Integer, Deed> deeds = new LinkedHashMap<>();
    List<Integer> dice = new ArrayList<>(),
        chance = new ArrayList<>(),
        chest = new ArrayList<>(),
        bankAuctions = new ArrayList<>();
    List<Bill> bills = new ArrayList<>();
    List<Trade> trades = new ArrayList<>();
    Auction auction;
    Bill lastPayment;
    String drawnCard;
    Set<String> actionIds = new HashSet<>();
    List<GameEvent> events = new ArrayList<>();
    boolean rollAgain;

    Data() {}

    Data(Data d) {
      config = d.config;
      seed = d.seed;
      rollCount = d.rollCount;
      revision = d.revision;
      turnIndex = d.turnIndex;
      turnNumber = d.turnNumber;
      doubles = d.doubles;
      phase = d.phase;
      message = d.message;
      winner = d.winner;
      resume = d.resume;
      rollAgain = d.rollAgain;
      auction = d.auction;
      lastPayment = d.lastPayment;
      drawnCard = d.drawnCard;
      players = new ArrayList<>(d.players);
      people = new LinkedHashMap<>(d.people);
      deeds = new LinkedHashMap<>(d.deeds);
      dice = new ArrayList<>(d.dice);
      chance = new ArrayList<>(d.chance);
      chest = new ArrayList<>(d.chest);
      bankAuctions = new ArrayList<>(d.bankAuctions);
      bills = new ArrayList<>(d.bills);
      trades = new ArrayList<>(d.trades);
      actionIds = new HashSet<>(d.actionIds);
      events = new ArrayList<>(d.events);
    }

    String turn() {
      return players.get(turnIndex);
    }
  }

  /** Server-only durable state. Never use this record as a player/spectator response. */
  public record Checkpoint(int version,
      MonopolyConfig config,
      long seed,
      int rollCount,
      int revision,
      int turnIndex,
      int turnNumber,
      int doubles,
      String phase,
      String message,
      String winner,
      String resume,
      List<String> players,
      Map<String, Player> people,
      Map<Integer, Deed> deeds,
      List<Integer> dice,
      List<Integer> chance,
      List<Integer> chest,
      List<Integer> bankAuctions,
      List<Bill> bills,
      List<Trade> trades,
      Auction auction,
      Bill lastPayment,
      String drawnCard,
      Set<String> actionIds,
      List<GameEvent> events,
      boolean rollAgain) {}

  public Checkpoint checkpoint() {
    Data d = copy();
    return new Checkpoint(1,
        d.config,
        d.seed,
        d.rollCount,
        d.revision,
        d.turnIndex,
        d.turnNumber,
        d.doubles,
        d.phase,
        d.message,
        d.winner,
        d.resume,
        d.players,
        d.people,
        d.deeds,
        d.dice,
        d.chance,
        d.chest,
        d.bankAuctions,
        d.bills,
        d.trades,
        d.auction,
        d.lastPayment,
        d.drawnCard,
        d.actionIds,
        d.events,
        d.rollAgain);
  }

  public static MonopolyState restore(Checkpoint saved) {
    if (saved.version() != 1 || saved.config() == null || saved.players() == null
        || saved.players().size() < 2 || saved.players().size() > MonopolyConfig.MAX_PLAYERS
        || saved.turnIndex() < 0 || saved.turnIndex() >= saved.players().size()
        || saved.people() == null || !saved.people().keySet().equals(new HashSet<>(saved.players()))) {
      throw new IllegalArgumentException("Invalid Huudpoly checkpoint");
    }
    Data d = new Data();
    d.config = saved.config();
    d.seed = saved.seed();
    d.rollCount = saved.rollCount();
    d.revision = saved.revision();
    d.turnIndex = saved.turnIndex();
    d.turnNumber = saved.turnNumber();
    d.doubles = saved.doubles();
    d.phase = saved.phase();
    d.message = saved.message();
    d.winner = saved.winner();
    d.resume = saved.resume();
    d.players = saved.players();
    d.people = saved.people();
    d.deeds = saved.deeds();
    d.dice = saved.dice();
    d.chance = saved.chance();
    d.chest = saved.chest();
    d.bankAuctions = saved.bankAuctions();
    d.bills = saved.bills();
    d.trades = saved.trades();
    d.auction = saved.auction();
    d.lastPayment = saved.lastPayment();
    d.drawnCard = saved.drawnCard();
    d.actionIds = saved.actionIds();
    d.events = saved.events();
    d.rollAgain = saved.rollAgain();
    return new MonopolyState(d);
  }

  private final Data frozen;

  MonopolyState(Data d) {
    frozen = new Data(d);
  }

  Data copy() {
    return new Data(frozen);
  }

  @Override
  public String phase() {
    return frozen.phase;
  }

  @Override
  public int round() {
    return frozen.revision;
  }

  @Override
  public boolean finished() {
    return frozen.winner != null;
  }

  @Override
  public List<GameEvent> events() {
    return List.copyOf(frozen.events);
  }
}
