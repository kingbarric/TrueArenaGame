import 'slay_models.dart';

/// Browsing metadata is separate from equipped slots and scoring tags, so old
/// saved looks and purchases remain valid after duplicate tiles are merged.
class SlayWardrobe {
  SlayWardrobe(Map<String, dynamic> catalog, String body)
      : _presentation =
            Map<String, dynamic>.from(catalog['wardrobePresentation'] ?? {}) {
    final available = (catalog['items'] as List)
        .cast<Map>()
        .where((item) =>
            item['assetUrl'] != null &&
            (item['body'] == body || item['body'] == 'unisex'))
        .toList();
    final ids = available.map((item) => item['id']).toSet();
    final seen = <String, String>{};
    for (final item in available) {
      final canonical =
          _entry(item['id'])['duplicateOf'] as String? ?? item['id'] as String;
      if (canonical != item['id'] && ids.contains(canonical)) {
        _aliases[item['id']] = canonical;
        continue;
      }
      // Also handle an exact shared asset URL in older catalogues.
      final key = '${item['body']}:${item['assetUrl']}';
      if (seen.containsKey(key)) {
        _aliases[item['id']] = seen[key]!;
      } else {
        seen[key] = item['id'];
        items.add(item);
      }
    }
    _byId = {for (final item in available) item['id'] as String: item};
  }
  final Map<String, dynamic> _presentation;
  late final Map<String, Map> _byId;
  final List<Map> items = [];
  final Map<String, String> _aliases = {};
  static const clothing = {
    'outfit',
    'dress',
    'tops',
    'shirts',
    'trousers',
    'skirts'
  };

  Map _entry(String id) => _presentation[id] as Map? ?? {};
  String canonicalId(String id) => _aliases[id] ?? id;
  String category(Map item) =>
      _entry(item['id'])['category'] as String? ?? item['category'] as String;
  String group(Map item) =>
      _entry(item['id'])['styleGroup'] as String? ?? slayPrimaryStyle(item);
  String? categoryForId(String id) {
    final item = _byId[canonicalId(id)] ?? _byId[id];
    return item == null ? null : category(item);
  }

  Set<String> get categories => items.map(category).toSet();
  List<String> groupsFor(String category) => !clothing.contains(category)
      ? []
      : [
          for (final groupName in slayStyleGroups.keys)
            if (items.any((item) =>
                this.category(item) == category && group(item) == groupName))
              groupName,
        ];
  List<Map> itemsFor(String category, [String? style]) => items
      .where((item) =>
          this.category(item) == category &&
          (style == null || group(item) == style))
      .toList();
}
