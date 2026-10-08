import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../onboarding/guest_gate.dart';
import 'social_huud_models.dart';
import 'social_huud_screen.dart';

Future<SocialHuud?> socialHuudForRoom(ApiClient api, String roomId) async {
  try {
    final raw = await api.get('/huuds/sessions/by-game/$roomId');
    return raw is Map ? SocialHuud.fromJson(raw.cast<String, dynamic>()) : null;
  } on ApiException catch (e) {
    if (e.status == 404) return null;
    rethrow;
  }
}

/// Game taps always resolve the owned session first, never the currently viewed Huud.
Future<void> openOwnedHuud(BuildContext context, {String? gameType}) async {
  if (!await canHostOrPromptToVerify(context) || !context.mounted) return;
  final app = AppScope.of(context);
  final type = gameType == 'bluff' ? 'wordbluff' : gameType;
  try {
    final existing = await app.api.get('/huuds/sessions/owned');
    if (!context.mounted) return;
    Map<String, dynamic>? raw;
    if (existing is Map) {
      raw = existing.cast<String, dynamic>();
      if (raw['activity'] == 'idle' && type != null) {
        try {
          raw = (await app.api.post('/huuds/sessions/${raw['id']}/game', {
            'gameType': type,
            'activityVersion': raw['activityVersion']
          }) as Map)
              .cast<String, dynamic>();
        } on ApiException catch (e) {
          if (e.status != 409) rethrow;
          raw = (await app.api.get('/huuds/sessions/owned') as Map)
              .cast<String, dynamic>();
        }
      }
    } else {
      final body = await showCreateHuudPrompt(context, gameType: type);
      if (body == null) return;
      raw = (await app.api.post('/huuds/sessions', body) as Map)
          .cast<String, dynamic>();
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SocialHuudScreen(initial: SocialHuud.fromJson(raw!))));
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open your Huud. Try again.')));
    }
  }
}

Future<Map<String, dynamic>?> showCreateHuudPrompt(BuildContext context,
    {String? gameType, SocialHuud? edit}) async {
  final app = AppScope.of(context);
  final name = TextEditingController(
      text: edit?.name ?? "${app.user?.username ?? 'Player'}'s Huud");
  final description = TextEditingController(text: edit?.description ?? '');
  String privacy = edit?.privacy ?? 'public';
  final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
                title: Text(edit == null ? 'Create Huud' : 'Edit Huud'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: name,
                      maxLength: 80,
                      decoration: const InputDecoration(labelText: 'Name')),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'public', label: Text('Public')),
                        ButtonSegment(value: 'friends', label: Text('Friends')),
                        ButtonSegment(value: 'private', label: Text('Private')),
                      ],
                      selected: {
                        privacy
                      },
                      onSelectionChanged: (v) =>
                          setState(() => privacy = v.first)),
                  const SizedBox(height: 8),
                  Text(switch (privacy) {
                    'friends' => 'Friends can discover and request to join.',
                    'private' => 'Invite or code only.',
                    _ => 'Anyone can discover and watch.'
                  }),
                  const SizedBox(height: 12),
                  TextField(
                      controller: description,
                      maxLength: 280,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'Description (optional)')),
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, {
                            'name': name.text.trim(),
                            'privacy': privacy,
                            'description': description.text.trim(),
                            if (gameType != null) 'gameType': gameType,
                          }),
                      child: Text(edit == null ? 'Create Huud' : 'Save'))
                ],
              )));
  // Controllers remain alive until the dialog's closing animation finishes.
  Future<void>.delayed(const Duration(seconds: 1), () {
    name.dispose();
    description.dispose();
  });
  return result;
}
