import '../../core/api_client.dart';
import 'competitive_models.dart';

/// Thin typed wrapper over the competitive endpoints. Read-only apart from
/// [updateLocation] — ratings, ranks and achievements are server-computed.
class CompetitiveApi {
  const CompetitiveApi(this.api);
  final ApiClient api;

  Future<CompetitiveProfile> mine() async =>
      CompetitiveProfile.fromJson((await api.get('/me/competitive') as Map).cast<String, dynamic>());

  Future<CompetitiveProfile> player(String username) async => CompetitiveProfile.fromJson(
      (await api.get('/players/${Uri.encodeComponent(username)}/competitive') as Map).cast<String, dynamic>());

  Future<CompetitiveProfile> updateLocation({
    String? countryCode,
    String? regionCode,
    String? regionName,
    String? city,
    bool? cityPublic,
    bool? profilePublic,
  }) async {
    final res = await api.patch('/me/competitive', {
      if (countryCode != null) 'countryCode': countryCode,
      if (regionCode != null) 'regionCode': regionCode,
      if (regionName != null) 'regionName': regionName,
      if (city != null) 'city': city,
      if (cityPublic != null) 'cityPublic': cityPublic,
      if (profilePublic != null) 'profilePublic': profilePublic,
    });
    return CompetitiveProfile.fromJson((res as Map).cast<String, dynamic>());
  }

  Future<Leaderboard> leaderboard(String gameType,
      {LeaderboardScope scope = LeaderboardScope.global, String? key, int limit = 25, int offset = 0}) async {
    final q = 'scope=${scope.wire}&limit=$limit&offset=$offset${key == null ? '' : '&key=${Uri.encodeComponent(key)}'}';
    return Leaderboard.fromJson((await api.get('/leaderboards/$gameType?$q') as Map).cast<String, dynamic>());
  }

  Future<List<MatchHistoryEntry>> myMatches({String? gameType, int limit = 20}) async {
    final q = 'limit=$limit${gameType == null ? '' : '&gameType=$gameType'}';
    final rows = await api.get('/me/matches?$q') as List;
    return rows.map((e) => MatchHistoryEntry.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<List<MatchHistoryEntry>> playerMatches(String username, {String? gameType, int limit = 20}) async {
    final q = 'limit=$limit${gameType == null ? '' : '&gameType=$gameType'}';
    final rows = await api.get('/players/${Uri.encodeComponent(username)}/matches?$q') as List;
    return rows.map((e) => MatchHistoryEntry.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<List<String>> ratedGames() async =>
      ((await api.get('/competitive/games') as List)).map((e) => e as String).toList();

  Future<List<CountryOption>> countries() async {
    final rows = await api.get('/competitive/locations') as List;
    return rows.map((e) {
      final m = (e as Map).cast<String, dynamic>();
      return CountryOption(m['code'] as String, m['name'] as String, catalogued: m['catalogued'] as bool? ?? false);
    }).toList();
  }

  Future<List<RegionOption>> regions(String countryCode) async {
    final rows = await api.get('/competitive/locations/$countryCode') as List;
    return rows.map((e) {
      final m = (e as Map).cast<String, dynamic>();
      return RegionOption(m['code'] as String, m['name'] as String);
    }).toList();
  }
}
