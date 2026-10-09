import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../onboarding/guest_gate.dart';
import 'huud_kit.dart';
import 'huud_space_models.dart';
import 'huud_space_screen.dart';

/// Opens the "Make a Huud" sheet and, once made, walks straight into it.
/// Hosting a Huud already? The server hands that one back instead of making
/// a second, so this is also "take me to my Huud".
Future<void> startHuud(BuildContext context) async {
  if (!await canHostOrPromptToVerify(context)) return;
  if (!context.mounted) return;
  final made = await showHuudSheet<HuudSpace>(
    context,
    builder: (_) => const CreateHuudSheet(),
  );
  if (made == null || !context.mounted) return;
  await openHuudSpace(context, made.id, initial: made);
}

/// Just two questions: what's it called, and who can join.
class CreateHuudSheet extends StatefulWidget {
  const CreateHuudSheet({super.key});

  @override
  State<CreateHuudSheet> createState() => _CreateHuudSheetState();
}

class _CreateHuudSheetState extends State<CreateHuudSheet> {
  final _name = TextEditingController();
  HuudPrivacy _privacy = HuudPrivacy.friends;
  bool _busy = false;
  String? _error;
  bool _filled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
    final user = AppScope.of(context).user;
    final first =
        (user?.displayName.isNotEmpty == true ? user!.displayName : (user?.username ?? 'My')).split(' ').first;
    _name.text = first.endsWith('s') ? "$first' Huud" : "$first's Huud";
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final raw = await AppScope.of(context).api.post('/huud-spaces', {
        'name': _name.text.trim(),
        'privacy': _privacy.wire,
      }) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.of(context).pop(HuudSpace.fromJson(raw));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "We couldn't reach PlayHuud. Check your internet and try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('🎉', textAlign: TextAlign.center, style: TextStyle(fontSize: 44)),
            const SizedBox(height: 4),
            Text('Make a Huud',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: n.ink)),
            const SizedBox(height: 4),
            Text('A place to hang out and play games together',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: n.mid)),
            const SizedBox(height: 22),
            _label(n, '1', 'Give it a name'),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('huud-name'),
              controller: _name,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: n.ink),
              decoration: InputDecoration(
                counterText: '',
                prefixIcon: Icon(Icons.edit_rounded, color: h.orangeText),
                suffixIcon: _name.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear name',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(_name.clear),
                      ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(color: h.orange, width: 2.4),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 18),
            _label(n, '2', 'Who can join?'),
            const SizedBox(height: 8),
            for (final p in HuudPrivacy.values) ...[
              _PrivacyChoice(
                privacy: p,
                selected: _privacy == p,
                onTap: () => setState(() => _privacy = p),
              ),
              const SizedBox(height: 10),
            ],
            if (_privacy == HuudPrivacy.public)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('🛡️ Anyone can come in. Be kind, and never share your address or phone number.',
                    style: TextStyle(fontSize: 14, height: 1.35, color: n.mid)),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: n.danger)),
              ),
            const SizedBox(height: 6),
            HuudButton(
              key: const ValueKey('huud-create'),
              label: 'Make my Huud',
              icon: Icons.celebration_rounded,
              big: true,
              expand: true,
              busy: _busy,
              onPressed: _create,
            ),
          ]),
        ),
      ),
    );
  }

  Widget _label(NeonColors n, String step, String text) {
    final h = HuudColors.of(context);
    return Row(children: [
      Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration:
            BoxDecoration(color: h.orange, shape: BoxShape.circle, border: Border.all(color: kCabinetInk, width: 2)),
        child: Text(step, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: h.onOrange)),
      ),
      const SizedBox(width: 10),
      Text(text, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: n.ink)),
    ]);
  }
}

class _PrivacyChoice extends StatelessWidget {
  const _PrivacyChoice({required this.privacy, required this.selected, required this.onTap});
  final HuudPrivacy privacy;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    return Semantics(
      selected: selected,
      button: true,
      label: '${privacy.label}. ${privacy.explain}',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('huud-privacy-${privacy.wire}'),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? h.orangeSoft : n.panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? h.orange : n.line, width: selected ? 2.6 : 1.4),
          ),
          child: Row(children: [
            Text(privacy.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(privacy.label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: n.ink)),
                const SizedBox(height: 2),
                Text(privacy.explain, style: TextStyle(fontSize: 14, color: n.mid)),
              ]),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? h.orange : Colors.transparent,
                border: Border.all(color: selected ? kCabinetInk : n.mute, width: 2),
              ),
              child: selected ? Icon(Icons.check_rounded, size: 18, color: h.onOrange) : null,
            ),
          ]),
        ),
      ),
    );
  }
}
