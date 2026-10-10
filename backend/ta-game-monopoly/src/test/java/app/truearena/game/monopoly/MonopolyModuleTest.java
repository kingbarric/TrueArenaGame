package app.truearena.game.monopoly;

import static org.junit.jupiter.api.Assertions.*;

import app.truearena.engine.*;
import app.truearena.game.monopoly.MonopolyState.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.file.*;
import java.util.*;
import org.junit.jupiter.api.Test;

class MonopolyModuleTest {
  final MonopolyModule game = new MonopolyModule();

  MonopolyState start() {
    return (MonopolyState)
        game.initialState(
            List.of("eric", "ada", "chidi", "sarah"),
            MonopolyConfig.defaults(),
            RandomSource.seeded(9));
  }

  MonopolyState act(GameState s, String who, String type, Map<String, Object> data) {
    return (MonopolyState) game.onPlayerAction(s, PlayerAction.of(who, type, data));
  }

  MonopolyState act(GameState s, String who, String type) {
    return act(s, who, type, Map.of());
  }

  MonopolyState fixture(java.util.function.Consumer<Data> setup) {
    Data d = start().copy();
    setup.accept(d);
    return new MonopolyState(d);
  }

  @Test
  void rosterCapacityAndAuthority() {
    assertThrows(
        RuleViolation.class,
        () -> game.initialState(List.of("a"), MonopolyConfig.defaults(), RandomSource.seeded(0)));
    assertThrows(
        RuleViolation.class,
        () ->
            game.initialState(
                List.of("a", "a"), MonopolyConfig.defaults(), RandomSource.seeded(0)));
    assertThrows(
        RuleViolation.class,
        () ->
            game.initialState(
                java.util.stream.IntStream.range(0, 9).mapToObj(Integer::toString).toList(),
                MonopolyConfig.defaults(),
                RandomSource.seeded(0)));
    MonopolyState s = start();
    assertThrows(RuleViolation.class, () -> act(s, "ada", "ROLL"));
    assertThrows(RuleViolation.class, () -> act(s, "viewer", "ROLL"));
    assertEquals(1500, s.copy().people.get("eric").cash());
    assertEquals("Roll", s.phase());
  }

  @Test
  void purchaseChargesPrintedPriceAndLocksOwnership() {
    MonopolyState s =
        fixture(
            d -> {
              d.phase = "Purchase";
              d.people.put("eric", d.people.get("eric").move(24));
            });
    MonopolyState next = act(s, "eric", "BUY");
    assertEquals(1260, next.copy().people.get("eric").cash());
    assertEquals("eric", next.copy().deeds.get(24).owner());
    assertNull(s.copy().deeds.get(24).owner());
    assertThrows(RuleViolation.class, () -> act(next, "eric", "BUY"));
  }

  @Test
  void duplicateActionsDoNotChargeTwiceAndRollsAreReproducible() {
    MonopolyState s = start();
    PlayerAction a = PlayerAction.of("eric", "ROLL", Map.of("dice", List.of(6, 6)));
    GameState next = game.onPlayerAction(s, a);
    assertSame(next, game.onPlayerAction(next, a));
    assertEquals(game.broadcastState(next), game.broadcastState(game.onPlayerAction(start(), a)));
    assertEquals(1, ((MonopolyState) next).copy().rollCount);
  }

  @Test
  void auctionIncludesDeclinerAndOnlyChargesWinner() {
    MonopolyState s =
        fixture(
            d -> {
              d.phase = "Purchase";
              d.people.put("eric", d.people.get("eric").move(39));
            });
    s = act(s, "eric", "AUCTION");
    s = act(s, "eric", "BID", Map.of("amount", 10));
    s = act(s, "ada", "BID", Map.of("amount", 20));
    final MonopolyState live = s;
    assertThrows(RuleViolation.class, () -> act(live, "chidi", "BID", Map.of("amount", 20)));
    assertThrows(RuleViolation.class, () -> act(live, "sarah", "PASS"));
    s = act(s, "chidi", "PASS");
    s = act(s, "sarah", "PASS");
    s = act(s, "eric", "PASS");
    assertEquals("ada", s.copy().deeds.get(39).owner());
    assertEquals(1480, s.copy().people.get("ada").cash());
    assertEquals(1500, s.copy().people.get("eric").cash());
    assertEquals("Manage", s.phase());
  }

  @Test
  void noBidLeavesDeedInBankAndFractionalBidRejected() {
    MonopolyState s =
        fixture(
            d -> {
              d.phase = "Purchase";
              d.people.put("eric", d.people.get("eric").move(1));
            });
    s = act(s, "eric", "AUCTION");
    final MonopolyState live = s;
    assertThrows(RuleViolation.class, () -> act(live, "eric", "BID", Map.of("amount", 10.5)));
    for (String id : List.of("eric", "ada", "chidi", "sarah")) s = act(s, id, "PASS");
    assertNull(s.copy().deeds.get(1).owner());
  }

  @Test
  void completeGroupsDoubleBareRentButMortgageOnlyStopsItsOwnRent() {
    Data d =
        fixture(
                x -> {
                  x.dice = List.of(3, 4);
                  x.deeds.put(1, new Deed("ada", 0, false));
                  x.deeds.put(3, new Deed("ada", 0, true));
                })
            .copy();
    assertEquals(4, MonopolyModule.rent(d, 1));
    assertEquals(0, MonopolyModule.rent(d, 3));
    for (int id : List.of(5, 15, 25, 35)) d.deeds.put(id, new Deed("ada", 0, false));
    assertEquals(200, MonopolyModule.rent(d, 5));
    d.deeds.put(12, new Deed("ada", 0, false));
    assertEquals(28, MonopolyModule.rent(d, 12));
    d.deeds.put(28, new Deed("ada", 0, true));
    assertEquals(70, MonopolyModule.rent(d, 12));
  }

  @Test
  void buildEvenlyAndReturnStockAfterHotel() {
    MonopolyState s =
        fixture(
            d -> {
              d.phase = "Manage";
              d.people.put("eric", d.people.get("eric").cash(5000));
              d.deeds.put(1, new Deed("eric", 0, false));
              d.deeds.put(3, new Deed("eric", 0, false));
            });
    s = act(s, "eric", "BUILD", Map.of("property", 1));
    final MonopolyState uneven = s;
    assertThrows(RuleViolation.class, () -> act(uneven, "eric", "BUILD", Map.of("property", 1)));
    assertThrows(RuleViolation.class, () -> act(uneven, "eric", "MORTGAGE", Map.of("property", 3)));
    s = act(s, "eric", "BUILD", Map.of("property", 3));
    for (int i = 0; i < 4; i++) {
      s = act(s, "eric", "BUILD", Map.of("property", 1));
      s = act(s, "eric", "BUILD", Map.of("property", 3));
    }
    assertEquals(5, s.copy().deeds.get(1).buildings());
    assertEquals(32, game.broadcastState(s).data().get("bankHouses"));
    assertEquals(10, game.broadcastState(s).data().get("bankHotels"));
    s = act(s, "eric", "SELL_BUILDING", Map.of("property", 1));
    assertEquals(28, game.broadcastState(s).data().get("bankHouses"));
    assertEquals(11, game.broadcastState(s).data().get("bankHotels"));
  }

  @Test
  void bankHouseShortageAndBulkGroupSaleAreSafe() {
    MonopolyState s =
        fixture(
            d -> {
              d.phase = "Manage";
              for (int id : List.of(6, 8, 9, 11, 13, 14, 16, 18))
                d.deeds.put(id, new Deed("ada", 4, false));
              d.deeds.put(1, new Deed("eric", 5, false));
              d.deeds.put(3, new Deed("eric", 5, false));
            });
    assertEquals(0, game.broadcastState(s).data().get("bankHouses"));
    assertThrows(RuleViolation.class, () -> act(s, "eric", "SELL_BUILDING", Map.of("property", 1)));
    MonopolyState sold = act(s, "eric", "SELL_GROUP", Map.of("property", 1));
    assertEquals(1750, sold.copy().people.get("eric").cash());
    assertEquals(12, game.broadcastState(sold).data().get("bankHotels"));
  }

  @Test
  void mortgageAndRedemptionChargeTenPercentInterest() {
    MonopolyState s =
        fixture(
            d -> {
              d.deeds.put(39, new Deed("eric", 0, false));
            });
    s = act(s, "eric", "MORTGAGE", Map.of("property", 39));
    assertEquals(1700, s.copy().people.get("eric").cash());
    s = act(s, "eric", "UNMORTGAGE", Map.of("property", 39));
    assertEquals(1480, s.copy().people.get("eric").cash());
    assertFalse(s.copy().deeds.get(39).mortgaged());
  }

  @Test
  void tradeOffersStayPrivateAndTransferInterestIsPaidAtomically() {
    MonopolyState s =
        fixture(
            d -> {
              d.deeds.put(39, new Deed("eric", 0, true));
            });
    s =
        act(
            s,
            "eric",
            "OFFER_TRADE",
            Map.of(
                "to",
                "ada",
                "giveCash",
                0,
                "takeCash",
                100,
                "giveDeeds",
                List.of(39),
                "takeDeeds",
                List.of()));
    assertFalse(game.broadcastState(s).data().containsKey("tradeOffers"));
    assertEquals(List.of(), game.visibleStateFor(s, "chidi").data().get("tradeOffers"));
    assertFalse(game.visibleStateFor(s, "viewer").data().containsKey("tradeOffers"));
    String id = s.copy().trades.getFirst().id();
    final MonopolyState offer = s;
    assertThrows(
        RuleViolation.class, () -> act(offer, "chidi", "ACCEPT_TRADE", Map.of("tradeId", id)));
    s = act(s, "ada", "ACCEPT_TRADE", Map.of("tradeId", id));
    assertEquals(1600, s.copy().people.get("eric").cash());
    assertEquals(1380, s.copy().people.get("ada").cash());
    assertEquals("ada", s.copy().deeds.get(39).owner());
    assertTrue(
        offer.events().stream()
            .filter(e -> e.type().equals("TRADE_OFFER"))
            .noneMatch(e -> e.visibility().isPublic()));
  }

  @Test
  void staleTradeCannotTakeADeedAfterItChangedHands() {
    MonopolyState s =
        fixture(
            d -> {
              d.deeds.put(1, new Deed("eric", 0, false));
            });
    s =
        act(
            s,
            "eric",
            "OFFER_TRADE",
            Map.of("to", "ada", "giveCash", 0, "takeCash", 40, "giveDeeds", List.of(1)));
    Data d = s.copy();
    String id = d.trades.getFirst().id();
    d.deeds.put(1, new Deed("chidi", 0, false));
    MonopolyState changed = new MonopolyState(d);
    assertThrows(
        RuleViolation.class, () -> act(changed, "ada", "ACCEPT_TRADE", Map.of("tradeId", id)));
    assertEquals(1500, changed.copy().people.get("ada").cash());
  }

  @Test
  void debtTimeoutLiquidatesInsteadOfEliminatingSolventPlayer() {
    MonopolyState s =
        fixture(
            d -> {
              d.phase = "Debt";
              d.people.put("eric", d.people.get("eric").cash(5));
              d.deeds.put(39, new Deed("eric", 0, false));
              d.bills.add(new Bill("eric", "ada", 100, "Rent"));
            });
    final MonopolyState solvent = s;
    assertThrows(RuleViolation.class, () -> act(solvent, "eric", "BANKRUPT"));
    s = (MonopolyState) game.onPhaseElapsed(s, "Debt");
    assertFalse(s.copy().people.get("eric").bankrupt());
    assertEquals(105, s.copy().people.get("eric").cash());
    assertEquals(1600, s.copy().people.get("ada").cash());
    assertTrue(s.copy().deeds.get(39).mortgaged());
  }

  @Test
  void bankruptcyToBankAuctionsTheEstateAndAdvancesTurn() {
    MonopolyState s =
        fixture(
            d -> {
              d.phase = "Debt";
              d.people.put("eric", d.people.get("eric").cash(0));
              d.deeds.put(1, new Deed("eric", 0, true));
              d.bills.add(new Bill("eric", null, 200, "Tax"));
            });
    s = act(s, "eric", "BANKRUPT");
    assertEquals("Auction", s.phase());
    assertFalse(s.copy().deeds.get(1).mortgaged());
    for (String id : List.of("ada", "chidi", "sarah")) s = act(s, id, "PASS");
    assertEquals("ada", s.copy().turn());
    assertEquals("Roll", s.phase());
  }

  @Test
  void bankruptcyToCreditorTransfersDeedsAndMortgageFees() {
    MonopolyState s =
        fixture(
            d -> {
              d.phase = "Debt";
              d.people.put("eric", d.people.get("eric").cash(0));
              d.deeds.put(39, new Deed("eric", 0, true));
              d.bills.add(new Bill("eric", "ada", 300, "Rent"));
            });
    s = act(s, "eric", "BANKRUPT");
    assertEquals("ada", s.copy().deeds.get(39).owner());
    assertEquals(1480, s.copy().people.get("ada").cash());
    assertEquals("Roll", s.phase());
  }

  @Test
  void jailEscapeHasNoBonusRollAndThirdFailureRequiresFine() {
    MonopolyState s =
        fixture(
            d -> {
              d.people.put("eric", new Player(1500, 10, true, 2, false, List.of()));
            });
    // Find a non-double server roll rather than supplying client dice.
    Data d = s.copy();
    for (long seed = 0; ; seed++) {
      d.seed = seed;
      MonopolyState trial = act(new MonopolyState(d), "eric", "ROLL");
      if (!trial.copy().dice.get(0).equals(trial.copy().dice.get(1))) {
        s = trial;
        break;
      }
    }
    assertEquals(1450, s.copy().people.get("eric").cash());
    assertFalse(s.copy().people.get("eric").jailed());
    assertFalse(s.copy().rollAgain);
    d =
        fixture(
                x -> {
                  x.people.put("eric", new Player(1500, 10, true, 0, false, List.of()));
                })
            .copy();
    for (long seed = 0; ; seed++) {
      d.seed = seed;
      MonopolyState trial = act(new MonopolyState(d), "eric", "ROLL");
      if (trial.copy().dice.get(0).equals(trial.copy().dice.get(1))) {
        assertFalse(trial.copy().rollAgain);
        assertFalse(trial.copy().people.get("eric").jailed());
        break;
      }
    }
  }

  @Test
  void thirdConsecutiveDoubleSendsToJailWithoutGoMoney() {
    Data d =
        fixture(
                x -> {
                  x.doubles = 2;
                  x.people.put("eric", x.people.get("eric").move(39));
                })
            .copy();
    for (long seed = 0; ; seed++) {
      d.seed = seed;
      MonopolyState trial = act(new MonopolyState(d), "eric", "ROLL");
      if (trial.copy().dice.get(0).equals(trial.copy().dice.get(1))) {
        assertTrue(trial.copy().people.get("eric").jailed());
        assertEquals(1500, trial.copy().people.get("eric").cash());
        assertEquals(10, trial.copy().people.get("eric").position());
        break;
      }
    }
  }

  @Test
  void spectatorProjectionNeverContainsFutureRandomnessOrOffers() throws Exception {
    String json = new ObjectMapper().writeValueAsString(game.broadcastState(start()).data());
    for (String secret :
        List.of("seed", "rollCount", "chance\": [", "chest\": [", "tradeOffers", "actionIds"))
      assertFalse(json.contains(secret), secret);
    Data d = start().copy();
    assertNotEquals(java.util.stream.IntStream.range(0, 16).boxed().toList(), d.chance);
  }

  @Test
  void longGamesPreserveMoneyPositionsStockAndDecisionProgress() {
    for (int seed = 0; seed < 12; seed++) {
      MonopolyState s =
          (MonopolyState)
              game.initialState(
                  List.of("a", "b", "c", "d"),
                  MonopolyConfig.defaults(),
                  RandomSource.seeded(seed));
      for (int step = 0; step < 4000 && !s.finished(); step++) {
        Data d = s.copy();
        String who = game.playersToAct(s).iterator().next();
        if (s.phase().equals("Purchase")
            && d.people.get(who).cash()
                >= MonopolyBoard.at(d.people.get(who).position()).price() + 100)
          s = act(s, who, "BUY");
        else s = (MonopolyState) game.onPhaseElapsed(s, s.phase());
        for (Player p : s.copy().people.values()) {
          assertTrue(p.cash() >= 0);
          assertTrue(p.position() >= 0 && p.position() < 40);
        }
        assertTrue((int) game.broadcastState(s).data().get("bankHouses") >= 0);
      }
      if (s.finished())
        assertEquals(
            1,
            game.checkWinCondition(s).orElseThrow().perPlayerOutcome().values().stream()
                .filter("won"::equals)
                .count());
      else
        assertFalse(game.playersToAct(s).isEmpty(), "a long game must still have a legal decision");
    }
  }

  @Test
  void finalInsolvencyProducesOneWinner() {
    MonopolyState s =
        (MonopolyState)
            game.initialState(List.of("a", "b"), MonopolyConfig.defaults(), RandomSource.seeded(0));
    Data d = s.copy();
    d.phase = "Debt";
    d.people.put("a", d.people.get("a").cash(0));
    d.bills.add(new Bill("a", "b", 100, "Rent"));
    s = act(new MonopolyState(d), "a", "BANKRUPT");
    assertTrue(s.finished());
    assertEquals("b", game.checkWinCondition(s).orElseThrow().winningSide());
    assertEquals(
        Map.of("a", "lost", "b", "won"),
        game.checkWinCondition(s).orElseThrow().perPlayerOutcome());
  }

  MonopolyState cardFixture(String deck, int card, java.util.function.Consumer<Data> setup) {
    Data d = start().copy();
    int total = act(start(), "eric", "ROLL").copy().dice.stream().mapToInt(Integer::intValue).sum();
    int destination = deck.equals("chance") ? 7 : 17;
    d.people.put("eric", d.people.get("eric").move(Math.floorMod(destination - total, 40)));
    List<Integer> cards = deck.equals("chance") ? d.chance : d.chest;
    cards.remove(Integer.valueOf(card));
    cards.addFirst(card);
    setup.accept(d);
    return act(new MonopolyState(d), "eric", "ROLL");
  }

  @Test
  void chanceNearestRailroadDoublesTheCorrectRent() {
    MonopolyState s =
        cardFixture(
            "chance",
            5,
            d -> {
              for (int id : List.of(5, 15, 25, 35)) d.deeds.put(id, new Deed("ada", 0, false));
            });
    assertEquals(15, s.copy().people.get("eric").position());
    assertEquals(400, s.copy().lastPayment.amount());
    assertEquals(1900, s.copy().people.get("ada").cash());
  }

  @Test
  void chanceUtilityUsesAFreshServerRollAndTenTimesItsValue() {
    MonopolyState s = cardFixture("chance", 7, d -> d.deeds.put(12, new Deed("ada", 0, false)));
    GameEvent roll =
        s.events().stream().filter(e -> e.type().equals("UTILITY_ROLL")).findFirst().orElseThrow();
    int total =
        ((List<?>) roll.payload().get("dice"))
            .stream().mapToInt(v -> ((Number) v).intValue()).sum();
    assertEquals(total * 10, s.copy().lastPayment.amount());
    assertEquals(2, s.copy().rollCount);
  }

  @Test
  void jailCardIsRemovedFromDeckUntilUsedAndCardDecksNeverLeak() {
    MonopolyState s = cardFixture("chance", 9, d -> {});
    assertEquals(List.of("chance"), s.copy().people.get("eric").jailCards());
    assertEquals(15, s.copy().chance.size());
    Data d = s.copy();
    d.phase = "Roll";
    Player p = d.people.get("eric");
    d.people.put("eric", new Player(p.cash(), 10, true, 0, false, p.jailCards()));
    s = act(new MonopolyState(d), "eric", "USE_JAIL_CARD");
    assertEquals(16, s.copy().chance.size());
    assertTrue(s.copy().people.get("eric").jailCards().isEmpty());
    assertFalse(s.copy().people.get("eric").jailed());
  }

  @Test
  void repairCardsChargeHousesAndHotelsSeparately() {
    MonopolyState s =
        cardFixture(
            "chance",
            12,
            d -> {
              d.deeds.put(1, new Deed("eric", 5, false));
              d.deeds.put(3, new Deed("eric", 4, false));
            });
    assertEquals(200, s.copy().lastPayment.amount());
    s =
        cardFixture(
            "chest",
            13,
            d -> {
              d.deeds.put(1, new Deed("eric", 5, false));
              d.deeds.put(3, new Deed("eric", 4, false));
            });
    assertEquals(275, s.copy().lastPayment.amount());
  }

  @Test
  void birthdayChargesEveryOtherActivePlayerExactlyOnce() {
    MonopolyState s = cardFixture("chest", 8, d -> {});
    assertEquals(1530, s.copy().people.get("eric").cash());
    for (String id : List.of("ada", "chidi", "sarah"))
      assertEquals(1490, s.copy().people.get(id).cash());
  }

  @Test
  void hugeDeedNumbersCannotWrapAroundToARealProperty() {
    MonopolyState s = fixture(d -> d.deeds.put(39, new Deed("eric", 0, false)));
    assertThrows(
        RuleViolation.class,
        () ->
            act(
                s,
                "eric",
                "OFFER_TRADE",
                Map.of(
                    "to",
                    "ada",
                    "giveCash",
                    0,
                    "takeCash",
                    1,
                    "giveDeeds",
                    List.of(4_294_967_335L))));
  }

  @Test
  void exportApprovedLayoutFixtureWhenRequested() throws Exception {
    String path = System.getProperty("monopoly.preview");
    if (path == null) return;
    MonopolyState s =
        fixture(
            d -> {
              d.turnIndex = 1;
              d.phase = "Purchase";
              d.dice = List.of(3, 4);
              d.people.put("ada", d.people.get("ada").move(24).cash(1260));
              d.people.put("eric", d.people.get("eric").move(6).cash(1480));
              d.people.put("chidi", d.people.get("chidi").move(35).cash(1320));
              d.people.put("sarah", d.people.get("sarah").move(16).cash(1540));
              for (int id : List.of(31, 32, 34)) d.deeds.put(id, new Deed("sarah", 2, false));
            });
    Path p = Path.of(path);
    Files.createDirectories(p.getParent());
    new ObjectMapper()
        .writerWithDefaultPrettyPrinter()
        .writeValue(p.toFile(), game.broadcastState(s).data());
  }
}
