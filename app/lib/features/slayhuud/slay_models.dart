import '../../core/api_client.dart';

class SlayLook {
  const SlayLook(
      {required this.body,
      required this.skinTone,
      required this.facePreset,
      required this.items,
      required this.pose,
      required this.background,
      this.itemColours = const {}});
  final String body, skinTone, facePreset, pose, background;
  final Map<String, String> items;
  final Map<String, String> itemColours;
  factory SlayLook.initial([String body = 'female']) => SlayLook(
      body: body,
      skinTone: '#623a27',
      facePreset: 'classic',
      items: {'hair': '$body-hair-0'},
      pose: 'signature',
      background: 'studio');
  factory SlayLook.fromJson(Map<String, dynamic> j) => SlayLook(
      body: j['body'],
      skinTone: j['skinTone'],
      facePreset: j['facePreset'],
      items: Map<String, String>.from(j['items']),
      itemColours: Map<String, String>.from(j['itemColours'] ?? {}),
      pose: j['pose'],
      background: j['background']);
  Map<String, dynamic> toJson() => {
        'body': body,
        'skinTone': skinTone,
        'facePreset': facePreset,
        'items': items,
        'itemColours': itemColours,
        'pose': pose,
        'background': background
      };
  SlayLook copy(
          {String? skinTone,
          String? facePreset,
          Map<String, String>? items,
          Map<String, String>? itemColours,
          String? pose,
          String? background}) =>
      SlayLook(
          body: body,
          skinTone: skinTone ?? this.skinTone,
          facePreset: facePreset ?? this.facePreset,
          items: Map.unmodifiable(items ?? this.items),
          itemColours: Map.unmodifiable({
            for (final entry in (itemColours ?? this.itemColours).entries)
              if ((items ?? this.items)[entry.key] == this.items[entry.key] &&
                  this.items.containsKey(entry.key))
                entry.key: entry.value
          }),
          pose: pose ?? this.pose,
          background: background ?? this.background);
  bool get isDressed =>
      items.containsKey('outfit') ||
      items.containsKey('dress') ||
      ((items.containsKey('tops') || items.containsKey('shirts')) &&
          (items.containsKey('trousers') || items.containsKey('skirts')));

  SlayLook equip(Map item, {Iterable<Map> wardrobe = const []}) {
    final next = {...items};
    final category = item['category'] as String;
    if (category == 'outfit' || category == 'dress') {
      for (final c in [
        'outfit',
        'dress',
        'tops',
        'shirts',
        'trousers',
        'skirts'
      ]) {
        next.remove(c);
      }
    } else if (['tops', 'shirts', 'trousers', 'skirts'].contains(category)) {
      next.remove('outfit');
      next.remove('dress');
    }
    if (['shirts', 'tops'].contains(category)) {
      next.remove(category == 'shirts' ? 'tops' : 'shirts');
    } else if (['trousers', 'skirts'].contains(category)) {
      next.remove(category == 'trousers' ? 'skirts' : 'trousers');
    }
    next[category] = item['id'];
    return copy(items: next);
  }
}

/// Wardrobe browsing uses the existing scoring tags; no second taxonomy in the DB.
const slayStyleGroups = <String, Set<String>>{
  'Casual': {'casual', 'streetwear', 'summer'},
  'Corporate': {'corporate', 'business'},
  'Date Night': {'romantic'},
  'Party': {'party', 'night'},
  'Formal': {'formal', 'elegant', 'luxury'},
  'Traditional': {'traditional', 'african', 'bridal', 'royal'},
};
String slayPrimaryStyle(Map item) {
  final tags = (item['styleTags'] as List? ?? []).cast<String>();
  for (final group in ['Traditional', 'Corporate']) {
    if (tags.any(slayStyleGroups[group]!.contains)) return group;
  }
  for (final tag in tags) {
    for (final group in slayStyleGroups.entries) {
      if (group.value.contains(tag)) return group.key;
    }
  }
  return 'Casual';
}

bool slayMatchesStyle(Map item, String group) =>
    slayPrimaryStyle(item) == group;

class SlayApi {
  SlayApi(this.client);
  final ApiClient client;
  Future<Map<String, dynamic>> catalog() async =>
      Map<String, dynamic>.from(await client.get('/slay/catalog'));
  Future<Map<String, dynamic>> profile() async =>
      Map<String, dynamic>.from(await client.get('/slay/profile'));
  Future<List<Map<String, dynamic>>> competitions() async =>
      (await client.get('/slay/competitions') as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  Future<Map<String, dynamic>> competition(String id) async =>
      Map<String, dynamic>.from(await client.get('/slay/competitions/$id'));
  Future<Map<String, dynamic>> room(String id) async =>
      Map<String, dynamic>.from(await client.get('/slay/rooms/$id'));
  Future<Map<String, dynamic>> action(String id, String action,
          [Map<String, dynamic>? data]) async =>
      Map<String, dynamic>.from(
          await client.post('/slay/competitions/$id/$action', data));
  Future<Map<String, dynamic>> create(
          String mode, String theme, int seats, String body) async =>
      Map<String, dynamic>.from(await client.post('/slay/competitions', {
        'mode': mode,
        'themeId': theme,
        'seats': seats,
        'contestantBody': body,
        'ranked': true
      }));
  Future<SlayLook> runwayLook(String id) async {
    final value = await client.get('/slay/looks/$id');
    return SlayLook.fromJson(Map<String, dynamic>.from(value['look']));
  }

  Future<String> save(SlayLook look, String image) async {
    final saved = await client.post('/slay/looks', look.toJson());
    final id = saved['id'] as String;
    await client.post('/slay/looks/$id/snapshot', {'pngBase64': image});
    return id;
  }

  Future<Map<String, dynamic>> score(String theme, String look) async =>
      Map<String, dynamic>.from(
          await client.post('/slay/solo/$theme/score', {'lookId': look}));
  Future<Map<String, dynamic>?> ballot(String id) async {
    final value = await client.get('/slay/competitions/$id/ballot');
    return value == null ? null : Map<String, dynamic>.from(value);
  }

  Future<void> vote(String ballot, String entry) async =>
      client.post('/slay/ballots/$ballot', {'entryId': entry});
  Future<void> report(String look, String reason) async =>
      client.post('/slay/reports', {'lookId': look, 'reason': reason});
  Future<void> block(String user) async =>
      client.post('/slay/blocks', {'userId': user});
  String imageUrl(String path) => '${ApiClient.base}/api/v1$path';
  Map<String, String> get imageHeaders =>
      {'authorization': 'Bearer ${client.bearer ?? ''}'};
}
