package app.truearena.game.monopoly;

import java.util.*;

/** One canonical board shared with clients through the safe snapshot. */
public final class MonopolyBoard {
  private MonopolyBoard() {}

  public record Space(
      int id,
      String name,
      String kind,
      String group,
      int price,
      int buildingCost,
      List<Integer> rents) {
    public boolean buyable() {
      return price > 0;
    }

    public int mortgage() {
      return price / 2;
    }
  }

  private static Space special(int id, String name, String kind) {
    return new Space(id, name, kind, "", 0, 0, List.of());
  }

  private static Space deed(
      int id, String name, String kind, String group, int price, int cost, Integer... rents) {
    return new Space(id, name, kind, group, price, cost, List.of(rents));
  }

  public static final List<Space> SPACES =
      List.of(
          special(0, "HUB", "go"),
          deed(1, "Lantern Lane", "street", "brown", 60, 50, 2, 10, 30, 90, 160, 250),
          special(2, "Neighbourhood", "chest"),
          deed(3, "Clay Court", "street", "brown", 60, 50, 4, 20, 60, 180, 320, 450),
          special(4, "Civic Levy", "tax"),
          deed(5, "Harbour Transit", "railroad", "railroad", 200, 0),
          deed(6, "Willow Walk", "street", "lightBlue", 100, 50, 6, 30, 90, 270, 400, 550),
          special(7, "Opportunity", "chance"),
          deed(8, "Maple Terrace", "street", "lightBlue", 100, 50, 6, 30, 90, 270, 400, 550),
          deed(9, "Fern Grove", "street", "lightBlue", 120, 50, 8, 40, 100, 300, 450, 600),
          special(10, "Jail / Just Visiting", "jail"),
          deed(11, "Orchid Square", "street", "pink", 140, 100, 10, 50, 150, 450, 625, 750),
          deed(12, "Solar Cooperative", "utility", "utility", 150, 0),
          deed(13, "Jasmine Row", "street", "pink", 140, 100, 10, 50, 150, 450, 625, 750),
          deed(14, "Lotus Gardens", "street", "pink", 160, 100, 12, 60, 180, 500, 700, 900),
          deed(15, "Skyline Transit", "railroad", "railroad", 200, 0),
          deed(16, "Ember Street", "street", "orange", 180, 100, 14, 70, 200, 550, 750, 950),
          special(17, "Neighbourhood", "chest"),
          deed(18, "Copper Crescent", "street", "orange", 180, 100, 14, 70, 200, 550, 750, 950),
          deed(19, "Sunset Market", "street", "orange", 200, 100, 16, 80, 220, 600, 800, 1000),
          special(20, "Rest Stop", "parking"),
          deed(21, "Coral Quay", "street", "red", 220, 150, 18, 90, 250, 700, 875, 1050),
          special(22, "Opportunity", "chance"),
          deed(23, "Ruby Arcade", "street", "red", 220, 150, 18, 90, 250, 700, 875, 1050),
          deed(24, "Saffron Square", "street", "red", 240, 150, 20, 100, 300, 750, 925, 1100),
          deed(25, "River Transit", "railroad", "railroad", 200, 0),
          deed(26, "Amber Heights", "street", "yellow", 260, 150, 22, 110, 330, 800, 975, 1150),
          deed(27, "Honeycomb Court", "street", "yellow", 260, 150, 22, 110, 330, 800, 975, 1150),
          deed(28, "Rainwater Cooperative", "utility", "utility", 150, 0),
          deed(29, "Golden Courtyard", "street", "yellow", 280, 150, 24, 120, 360, 850, 1025, 1200),
          special(30, "Go To Jail", "goToJail"),
          deed(31, "Cedar District", "street", "green", 300, 200, 26, 130, 390, 900, 1100, 1275),
          deed(
              32,
              "Juniper Ridge",
              "street",
              "green",
              300,
              200,
              26,
              130,
              390,
              900,
              1100,
              1275),
          special(33, "Neighbourhood", "chest"),
          deed(
              34,
              "Canopy Park",
              "street",
              "green",
              320,
              200,
              28,
              150,
              450,
              1000,
              1200,
              1400),
          deed(35, "Garden Transit", "railroad", "railroad", 200, 0),
          special(36, "Opportunity", "chance"),
          deed(37, "Starlight Plaza", "street", "darkBlue", 350, 200, 35, 175, 500, 1100, 1300, 1500),
          special(38, "Estate Levy", "tax"),
          deed(39, "Aurora Promenade", "street", "darkBlue", 400, 200, 50, 200, 600, 1400, 1700, 2000));

  public static Space at(int id) {
    if (id < 0 || id >= 40)
      throw new app.truearena.engine.RuleViolation("PROPERTY", "Choose a valid board space");
    return SPACES.get(id);
  }

  public static List<Space> group(Space space) {
    return SPACES.stream().filter(s -> s.group().equals(space.group()) && s.buyable()).toList();
  }
}
