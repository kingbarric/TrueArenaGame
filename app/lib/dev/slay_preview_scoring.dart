import '../features/slayhuud/slay_models.dart';

/// Offline preview counterpart of SlayRules.score. Production scores always
/// come from the backend. Shared contract fixtures test both implementations.
Map<String, dynamic> scoreSlayPreview(Map<String, dynamic> look,
    Map<String, dynamic> theme, Map<String, dynamic> catalog) {
  if (!(theme['bodyEligibility'] as List).contains(look['body'])) {
    throw StateError('This avatar is not eligible for the theme');
  }
  if (!SlayLook.fromJson(look).isDressed) {
    throw StateError('Complete your outfit before submitting');
  }
  final byId = {
    for (final item in catalog['items'] as List) item['id']: item as Map
  };
  final itemColours = Map<String, String>.from(look['itemColours'] ?? {});
  final palette = catalog['itemColourPalette'] as Map? ?? {};
  for (final colour in itemColours.entries) {
    if (!(look['items'] as Map).containsKey(colour.key) ||
        !{'shoes', 'tops', 'shirts'}.contains(colour.key) ||
        !palette.containsKey(colour.value)) {
      throw StateError(
          'Choose an available colour for your equipped shoes, shirt or top');
    }
  }
  final selected = <Map>[];
  for (final entry in (look['items'] as Map).entries) {
    final item = byId[entry.value];
    if (item == null || item['category'] != entry.key) {
      throw StateError('Item does not match its wardrobe category');
    }
    selected.add(item);
  }
  if (theme['budget'] != null &&
      selected.fold<num>(0, (sum, i) => sum + (i['coinCost'] as num)) >
          (theme['budget'] as num)) {
    throw StateError('Look exceeds the challenge budget');
  }
  const garmentCategories = {
    'outfit',
    'dress',
    'tops',
    'shirts',
    'trousers',
    'skirts'
  };
  const detailCategories = {
    'shoes',
    'headwear',
    'bags',
    'jewellery',
    'watches',
    'glasses',
    'accessories',
    'makeup'
  };
  final themeTags = (theme['styleTags'] as List).cast<String>();
  double match(Map item) {
    final tags = <String>{
      ...(item['styleTags'] as List).cast<String>(),
      ...(item['eventTags'] as List).cast<String>(),
      ...(item['cultureTags'] as List).cast<String>()
    };
    return themeTags.isEmpty
        ? 100
        : 100 * themeTags.where(tags.contains).length / themeTags.length;
  }

  double average(List<double> values, double fallback) => values.isEmpty
      ? fallback
      : values.reduce((a, b) => a + b) / values.length;
  double round(double value) => (value * 10).round() / 10;
  final garments =
      selected.where((i) => garmentCategories.contains(i['category'])).toList();
  final details =
      selected.where((i) => detailCategories.contains(i['category'])).toList();
  final garmentFit = average(garments.map(match).toList(), 0);
  final detailFit = average(
      details.map((i) => match(i) > 0 ? 100.0 : 0.0).toList(), garmentFit);
  final fit = .85 * garmentFit + .15 * detailFit;
  final categories = selected.map((i) => i['category']).toSet();
  if (categories.contains('dress') ||
      ((categories.contains('trousers') || categories.contains('skirts')) &&
          (categories.contains('tops') || categories.contains('shirts')))) {
    categories.add('outfit');
  }
  final required = (theme['requiredCategories'] as List).cast<String>();
  final missing = required.where((c) => !categories.contains(c)).toList();
  final requirements = required.isEmpty
      ? 100.0
      : 100.0 * (required.length - missing.length) / required.length;
  final colours = <String>{
    for (final item in [...garments, ...details])
      ...itemColours.containsKey(item['category'])
          ? [itemColours[item['category']]!]
          : (item['colourTags'] as List).cast<String>()
  }..removeAll({
      'black',
      'white',
      'grey',
      'gray',
      'navy',
      'gold',
      'silver',
      'brown',
      'beige',
      'cream',
      'ivory',
      'nude'
    });
  final colour = garments.isEmpty
      ? 0.0
      : (100.0 - (colours.length - 2).clamp(0, 100) * 20).clamp(20.0, 100.0);
  final completionSlots = {'outfit', 'shoes', ...required};
  final completeness = 100.0 *
      completionSlots.where(categories.contains).length /
      completionSlots.length;
  final cap = (100 - 25 * missing.length).clamp(0, 100);
  final overall = round(
      (.50 * fit + .25 * requirements + .15 * colour + .10 * completeness)
          .clamp(0.0, cap.toDouble()));
  final feedback = <String>[];
  if (missing.isNotEmpty) {
    feedback.add(
        'Missing required items: ${missing.join(', ')}. Score limited to $cap.');
  }
  for (final garment in garments) {
    final fit = match(garment);
    if (fit < 100) {
      feedback.add(
          '${garment['name']} matches ${fit.round()}% of the theme tags: ${themeTags.join(', ')}.');
    }
  }
  final mismatchedDetails =
      details.where((i) => match(i) == 0).map((i) => i['name']).toList();
  if (mismatchedDetails.isNotEmpty) {
    feedback.add('Details outside the theme: ${mismatchedDetails.join(', ')}.');
  }
  if (colours.length > 2) {
    feedback.add(
        'Your palette has ${colours.length} accent colours. Try two accents with neutrals.');
  }
  if (!categories.contains('shoes') && !missing.contains('shoes')) {
    feedback.add('Footwear would complete the look.');
  }
  if (feedback.isEmpty) {
    feedback.add('Your outfit, required items and palette match this brief.');
  }
  return {
    'themeFit': round(fit),
    'requirements': round(requirements),
    'colour': round(colour),
    'completeness': round(completeness),
    'overall': overall,
    'stars': overall >= 85
        ? 3
        : overall >= 65
            ? 2
            : overall >= 40
                ? 1
                : 0,
    'missing': missing,
    'feedback': feedback,
  };
}
