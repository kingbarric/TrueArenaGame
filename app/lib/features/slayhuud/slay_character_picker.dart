import 'package:flutter/material.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import 'slay_theme.dart';
import 'slay_models.dart';
import 'slay_stage.dart';
import 'slay_ui.dart';

class _RoundIcon extends StatelessWidget {
  const _RoundIcon(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SlayCabinet(
      onTap: onTap,
      feel: BouncyFeel.snap,
      semanticLabel: label,
      padding: const EdgeInsets.all(8),
      radius: 99,
      child: Icon(icon, size: 22, color: context.neon.ink));
}

/// Choose your star once; they stay for the whole career.
class SlayCharacterPicker extends StatefulWidget {
  const SlayCharacterPicker(
      {super.key,
      required this.catalog,
      required this.onChosen,
      this.career = true,
      this.allowedBodies});
  final Map<String, dynamic> catalog;
  final bool career;
  final Set<String>? allowedBodies;
  final Future<void> Function(String body, String avatarId) onChosen;
  @override
  State<SlayCharacterPicker> createState() => _SlayCharacterPickerState();
}

class _SlayCharacterPickerState extends State<SlayCharacterPicker> {
  final _stage = SlayStageController();
  int _index = 0;
  bool _busy = false;

  List<Map<String, dynamic>> get _avatars => (widget.catalog['avatars'] as List)
      .where((a) =>
          widget.allowedBodies == null ||
          widget.allowedBodies!.contains(a['body']))
      .map((a) => Map<String, dynamic>.from(a))
      .toList();

  SlayLook _lookFor(Map<String, dynamic> avatar) {
    final body = avatar['body'] as String;
    // Characters are shown as they start: underwear only, so nothing distorts.
    return SlayLook.initial(body).copy(
        avatarId: avatar['id'] ?? body,
        skinTone: avatar['naturalSkinTone'] as String?);
  }

  Future<void> _confirm() async {
    final avatar = _avatars[_index];
    final name = avatar['name'] ?? (avatar['body'] == 'male' ? 'him' : 'her');
    final sure = widget.career
        ? await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
                  title: Text('Start your career with $name?'),
                  content: const Text(
                      'Your star stays with you for the whole journey, from Starter Studio to Global Star.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Keep looking')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('That’s my star!')),
                  ],
                ))
        : true;
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onChosen(avatar['body'], avatar['id'] ?? avatar['body']);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final avatars = _avatars, avatar = avatars[_index];
    final name = avatar['name'] ?? (avatar['body'] == 'male' ? 'Him' : 'Her');
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Row(children: [
          _RoundIcon(
              icon: Icons.arrow_back_rounded,
              label: 'Back',
              onTap: () => Navigator.maybePop(context)),
          const Spacer(),
        ]),
      ),
      const SizedBox(height: 6),
      const SlayHeadline('Who’s your star?', size: 30),
      const SizedBox(height: 4),
      Text(
          widget.career
              ? 'Pick once. They’ll walk every runway with you.'
              : 'Choose your character for this look.',
          style: TextStyle(color: n.mute)),
      const SizedBox(height: 10),
      Expanded(
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SlayCabinet(
                padding: EdgeInsets.zero,
                radius: 28,
                gradient: SlayStageLook.of('studio').gradient,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: SlayStage(
                      catalog: widget.catalog,
                      look: _lookFor(avatar),
                      controller: _stage),
                ),
              ),
            ),
          ),
          for (final (alignment, step, icon) in [
            (Alignment.centerLeft, -1, Icons.chevron_left_rounded),
            (Alignment.centerRight, 1, Icons.chevron_right_rounded)
          ])
            Align(
              alignment: alignment,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _RoundIcon(
                    icon: icon,
                    label: step < 0 ? 'Previous star' : 'Next star',
                    onTap: () => setState(
                        () => _index = (_index + step) % avatars.length)),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      SlayHeadline(name, size: 24),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (int i = 0; i < avatars.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.all(3),
            width: i == _index ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
                color: i == _index ? n.brand : n.line,
                borderRadius: BorderRadius.circular(8)),
          ),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SizedBox(
          width: double.infinity,
          child: SlayButton.icon(
              onPressed: _busy ? null : _confirm,
              icon: const Icon(Icons.favorite_rounded),
              label: const Text('This is my star')),
        ),
      ),
    ]);
  }
}
