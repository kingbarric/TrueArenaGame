import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../../widgets/nav_art.dart';
import '../huudspace/huud_kit.dart';

/// The feed's existing friends-only post action, presented after tapping +.
class FeedPostComposer extends StatefulWidget {
  const FeedPostComposer({super.key});
  @override
  State<FeedPostComposer> createState() => _FeedPostComposerState();
}

class _FeedPostComposerState extends State<FeedPostComposer> {
  final _text = TextEditingController();
  bool _posting = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final body = _text.text.trim();
    if (_posting || body.isEmpty) return;
    if (body.length > 280) {
      setState(() => _error = 'Keep your post under 280 characters.');
      return;
    }
    setState(() {
      _posting = true;
      _error = null;
    });
    try {
      await AppScope.of(context).api.post('/huud/text-posts', {'body': body});
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _posting = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = userRetryMessage;
          _posting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final app = AppScope.of(context);
    final me = app.user?.username ?? app.user?.displayName ?? 'You';
    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 160),
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                      child: Text('New post',
                          style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: n.ink))),
                  IconButton(
                      tooltip: 'Close composer',
                      onPressed: _posting ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Avatar(me,
                      size: 40,
                      emoji: app.avatarEmoji,
                      imagePath: app.avatarImagePath,
                      imageUrl: app.user?.avatarUrl),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(me,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: n.ink)),
                        Row(children: [
                          const NavArt('friends', active: true, size: 16),
                          const SizedBox(width: 5),
                          Flexible(
                              child: Text('Only your friends see it',
                                  style:
                                      TextStyle(fontSize: 12, color: n.mute))),
                        ]),
                      ])),
                ]),
                TextField(
                  key: const ValueKey('feed-say'),
                  controller: _text,
                  autofocus: true,
                  maxLength: 280,
                  minLines: 3,
                  maxLines: 7,
                  enabled: !_posting,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: 17, height: 1.4, color: n.ink),
                  decoration: const InputDecoration(
                      hintText: 'What’s the conversation?',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 16)),
                ),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Semantics(
                          liveRegion: true,
                          child: Text(_error!,
                              style: TextStyle(color: n.danger)))),
                Align(
                    alignment: Alignment.centerRight,
                    child: HuudButton(
                        key: const ValueKey('feed-say-post'),
                        label: 'Post',
                        icon: Icons.arrow_upward_rounded,
                        busy: _posting,
                        onPressed: _text.text.trim().isEmpty || _posting
                            ? null
                            : _post)),
              ]),
        ),
      ),
    );
  }
}
