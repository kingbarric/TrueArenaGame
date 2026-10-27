/// Share artwork uses a first name; public games and feeds prefer a username.
String firstName(String? value, {String fallback = 'Player'}) {
  final name = value?.trim() ?? '';
  return name.isEmpty ? fallback : name.split(RegExp(r'\s+')).first;
}

String playerHandle(String? username, {String? displayName, String fallback = 'Player'}) {
  final handle = username?.trim() ?? '';
  return firstName(handle.isNotEmpty ? handle : displayName, fallback: fallback);
}
