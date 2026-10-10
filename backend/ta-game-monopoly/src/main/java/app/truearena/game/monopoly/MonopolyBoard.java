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
          special(0, "GO", "go"),
          deed(1, "Mediterranean Avenue", "street", "brown", 60, 50, 2, 10, 30, 90, 160, 250),
          special(2, "Community Chest", "chest"),
          deed(3, "Baltic Avenue", "street", "brown", 60, 50, 4, 20, 60, 180, 320, 450),
          special(4, "Income Tax", "tax"),
          deed(5, "Reading Railroad", "railroad", "railroad", 200, 0),
          deed(6, "Oriental Avenue", "street", "lightBlue", 100, 50, 6, 30, 90, 270, 400, 550),
          special(7, "Chance", "chance"),
          deed(8, "Vermont Avenue", "street", "lightBlue", 100, 50, 6, 30, 90, 270, 400, 550),
          deed(9, "Connecticut Avenue", "street", "lightBlue", 120, 50, 8, 40, 100, 300, 450, 600),
          special(10, "Jail / Just Visiting", "jail"),
          deed(11, "St. Charles Place", "street", "pink", 140, 100, 10, 50, 150, 450, 625, 750),
          deed(12, "Electric Company", "utility", "utility", 150, 0),
          deed(13, "States Avenue", "street", "pink", 140, 100, 10, 50, 150, 450, 625, 750),
          deed(14, "Virginia Avenue", "street", "pink", 160, 100, 12, 60, 180, 500, 700, 900),
          deed(15, "Pennsylvania Railroad", "railroad", "railroad", 200, 0),
          deed(16, "St. James Place", "street", "orange", 180, 100, 14, 70, 200, 550, 750, 950),
          special(17, "Community Chest", "chest"),
          deed(18, "Tennessee Avenue", "street", "orange", 180, 100, 14, 70, 200, 550, 750, 950),
          deed(19, "New York Avenue", "street", "orange", 200, 100, 16, 80, 220, 600, 800, 1000),
          special(20, "Free Parking", "parking"),
          deed(21, "Kentucky Avenue", "street", "red", 220, 150, 18, 90, 250, 700, 875, 1050),
          special(22, "Chance", "chance"),
          deed(23, "Indiana Avenue", "street", "red", 220, 150, 18, 90, 250, 700, 875, 1050),
          deed(24, "Illinois Avenue", "street", "red", 240, 150, 20, 100, 300, 750, 925, 1100),
          deed(25, "B. & O. Railroad", "railroad", "railroad", 200, 0),
          deed(26, "Atlantic Avenue", "street", "yellow", 260, 150, 22, 110, 330, 800, 975, 1150),
          deed(27, "Ventnor Avenue", "street", "yellow", 260, 150, 22, 110, 330, 800, 975, 1150),
          deed(28, "Water Works", "utility", "utility", 150, 0),
          deed(29, "Marvin Gardens", "street", "yellow", 280, 150, 24, 120, 360, 850, 1025, 1200),
          special(30, "Go To Jail", "goToJail"),
          deed(31, "Pacific Avenue", "street", "green", 300, 200, 26, 130, 390, 900, 1100, 1275),
          deed(
              32,
              "North Carolina Avenue",
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
          special(33, "Community Chest", "chest"),
          deed(
              34,
              "Pennsylvania Avenue",
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
          deed(35, "Short Line", "railroad", "railroad", 200, 0),
          special(36, "Chance", "chance"),
          deed(37, "Park Place", "street", "darkBlue", 350, 200, 35, 175, 500, 1100, 1300, 1500),
          special(38, "Luxury Tax", "tax"),
          deed(39, "Boardwalk", "street", "darkBlue", 400, 200, 50, 200, 600, 1400, 1700, 2000));

  public static Space at(int id) {
    if (id < 0 || id >= 40)
      throw new app.truearena.engine.RuleViolation("PROPERTY", "Choose a valid board space");
    return SPACES.get(id);
  }

  public static List<Space> group(Space space) {
    return SPACES.stream().filter(s -> s.group().equals(space.group()) && s.buyable()).toList();
  }
}
