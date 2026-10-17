import '../slayhuud/slay_models.dart';

class HuudAvatarChoice {
  const HuudAvatarChoice(
      {required this.id,
      required this.name,
      required this.body,
      required this.skinTone,
      required this.hair,
      this.thumbnailUrl});
  final String id, name, body, skinTone, hair;
  final String? thumbnailUrl;
  factory HuudAvatarChoice.fromJson(Map j) => HuudAvatarChoice(
      id: j['id'],
      name: j['name'],
      body: j['body'],
      skinTone: j['skinTone'],
      hair: j['hair'],
      thumbnailUrl: j['thumbnailUrl']);
}

class HuudOutfitChoice {
  const HuudOutfitChoice(
      {required this.id,
      required this.name,
      required this.female,
      required this.male,
      required this.colours,
      required this.swatch});
  final String id, name, swatch;
  final Map<String, String> female, male, colours;
  factory HuudOutfitChoice.fromJson(Map j) => HuudOutfitChoice(
      id: j['id'],
      name: j['name'],
      female: Map<String, String>.from(j['female']),
      male: Map<String, String>.from(j['male']),
      colours: Map<String, String>.from(j['colours']),
      swatch: j['swatch']);
}

class HuudAvatarOptions {
  const HuudAvatarOptions(this.avatars, this.outfits);
  final List<HuudAvatarChoice> avatars;
  final List<HuudOutfitChoice> outfits;
  factory HuudAvatarOptions.fromJson(Map j) => HuudAvatarOptions(
      [for (final a in j['avatars']) HuudAvatarChoice.fromJson(a)],
      [for (final o in j['outfits']) HuudOutfitChoice.fromJson(o)]);
  SlayLook? look(String? avatarId, String? outfitId) {
    final a = avatars.where((a) => a.id == avatarId).firstOrNull;
    final o = outfits.where((o) => o.id == outfitId).firstOrNull;
    if (a == null || o == null) return null;
    final items = {
      ...(a.body == 'female' ? o.female : o.male),
      'hair': a.hair,
      'shoes': 'shoe-1'
    };
    return SlayLook(
        body: a.body,
        avatarId: a.id,
        skinTone: a.skinTone,
        facePreset: 'classic',
        items: items,
        itemColours: {
          for (final entry in o.colours.entries)
            if (items.containsKey(entry.key)) entry.key: entry.value
        },
        pose: 'idle',
        background: 'studio');
  }
}
