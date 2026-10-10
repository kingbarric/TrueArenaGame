import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import 'huud_kit.dart';

/// Report or block someone, in words a ten-year-old can follow. Reports go to
/// the PlayHuud team with whatever message they were about; blocking keeps
/// you apart (no Huuds together, no chat from them, no friendship).
Future<void> showSafetySheet(
  BuildContext context, {
  required String userId,
  required String name,
  String? huudSpaceId,
  int? messageId,
  String? postId,
}) =>
    showHuudSheet<void>(
      context,
      builder: (_) =>
          _SafetySheet(userId: userId, name: name, huudSpaceId: huudSpaceId, messageId: messageId, postId: postId),
    );

const _reasons = [
  ('mean', '😠', 'Being mean'),
  ('unsafe', '⚠️', 'Made me feel unsafe'),
  ('spam', '📢', 'Spamming'),
  ('other', '🤔', 'Something else'),
];

class _SafetySheet extends StatefulWidget {
  const _SafetySheet({required this.userId, required this.name, this.huudSpaceId, this.messageId, this.postId});
  final String userId;
  final String name;
  final String? huudSpaceId;
  final int? messageId;
  final String? postId;

  @override
  State<_SafetySheet> createState() => _SafetySheetState();
}

class _SafetySheetState extends State<_SafetySheet> {
  bool _reporting = false;
  String? _reason;
  bool _alsoBlock = true;
  bool _busy = false;

  String get _first => widget.name.split(' ').first;

  Future<void> _send() async {
    if (_reason == null || _busy) return;
    setState(() => _busy = true);
    try {
      await AppScope.of(context).api.post('/players/${widget.userId}/report', {
        'reason': _reason,
        if (widget.huudSpaceId != null) 'huudSpaceId': widget.huudSpaceId,
        if (widget.messageId != null) 'messageId': widget.messageId,
        if (widget.postId != null) 'postId': widget.postId,
        'block': _alsoBlock,
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      huudSnack(context, _alsoBlock ? 'Thanks for telling us. $_first is blocked.' : 'Thanks for telling us.');
    } on ApiException catch (e) {
      if (mounted) huudSnack(context, e.message);
    } catch (_) {
      if (mounted) huudSnack(context, "That didn't send — try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _block() async {
    final ok = await confirmHuud(
      context,
      emoji: '🚫',
      title: 'Block $_first?',
      message: "You won't be in Huuds together, you won't see their chat, and you won't be friends.",
      yes: 'Block',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await AppScope.of(context).api.post('/players/${widget.userId}/block');
      if (!mounted) return;
      Navigator.of(context).pop();
      huudSnack(context, '$_first is blocked.');
    } on ApiException catch (e) {
      if (mounted) huudSnack(context, e.message);
    } catch (_) {
      if (mounted) huudSnack(context, "That didn't work — try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_reporting ? 'What happened?' : _first,
              textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: n.ink)),
          const SizedBox(height: 14),
          if (!_reporting) ...[
            HuudButton(
              key: const ValueKey('safety-report'),
              label: 'Report $_first',
              icon: Icons.flag_rounded,
              kind: HuudButtonKind.soft,
              expand: true,
              onPressed: () => setState(() => _reporting = true),
            ),
            const SizedBox(height: 10),
            HuudButton(
              key: const ValueKey('safety-block'),
              label: 'Block $_first',
              icon: Icons.block_rounded,
              kind: HuudButtonKind.danger,
              expand: true,
              busy: _busy,
              onPressed: _block,
            ),
          ] else ...[
            for (final (wire, emoji, label) in _reasons) ...[
              GestureDetector(
                key: ValueKey('safety-reason-$wire'),
                onTap: () => setState(() => _reason = wire),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: _reason == wire ? h.orangeSoft : n.panel,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _reason == wire ? h.orange : n.line, width: _reason == wire ? 2.4 : 1.4),
                  ),
                  child: Row(children: [
                    Text(emoji, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: n.ink)),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _alsoBlock,
              activeThumbColor: h.onOrange,
              activeTrackColor: h.orange,
              title:
                  Text('Also block $_first', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: n.ink)),
              onChanged: (v) => setState(() => _alsoBlock = v),
            ),
            if (_reason == 'unsafe')
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('💛 If someone makes you feel unsafe, tell a grown-up you trust too.',
                    style: TextStyle(fontSize: 14, height: 1.35, color: n.mid)),
              ),
            HuudButton(
              key: const ValueKey('safety-send'),
              label: 'Send report',
              icon: Icons.send_rounded,
              expand: true,
              big: true,
              busy: _busy,
              onPressed: _reason == null ? null : _send,
            ),
          ],
        ]),
      ),
    );
  }
}
