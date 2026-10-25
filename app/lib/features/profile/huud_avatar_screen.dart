import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import '../../core/api_client.dart' show userErrorMessage;
import '../../theme/neon_theme.dart';
import '../huudspace/huud_avatar_models.dart';
import '../slayhuud/slay_assets.dart';
import '../slayhuud/slay_models.dart';
import '../slayhuud/slay_stage.dart';

class HuudAvatarScreen extends StatefulWidget {
  const HuudAvatarScreen({super.key});
  @visibleForTesting
  static bool debugSkipAssetServer = false;
  @override
  State<HuudAvatarScreen> createState() => _HuudAvatarScreenState();
}

class _HuudAvatarScreenState extends State<HuudAvatarScreen> {
  final _stage = SlayStageController();
  HuudAvatarOptions? _options;
  Map<String, dynamic>? _catalog;
  String _avatar = 'male',
      _outfit = 'everyday',
      _savedAvatar = '',
      _savedOutfit = '';
  String? _error;
  bool _started = false,
      _busy = false,
      _pending = true,
      _previewFailed = false,
      _hasSaved = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _stage.ready.addListener(_onReady);
      unawaited(_load());
    }
  }

  void _onReady() {
    if (mounted) {
      setState(() {
        _pending = !_stage.ready.value;
        if (_stage.ready.value) _previewFailed = false;
      });
    }
  }

  @override
  void dispose() {
    _stage.ready.removeListener(_onReady);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final api = AppScope.of(context).api;
      final data = await Future.wait(
          [api.get('/me/huud-avatar'), SlayApi(api).catalog()]);
      if (!HuudAvatarScreen.debugSkipAssetServer) {
        await SlayAssets.instance.start();
      }
      if (!mounted) return;
      final profile = data[0] as Map;
      final options = HuudAvatarOptions.fromJson(profile['catalog']);
      setState(() {
        _options = options;
        _catalog = Map<String, dynamic>.from(data[1]);
        _avatar = profile['avatarId'];
        _outfit = profile['outfitId'];
        _savedAvatar = _avatar;
        _savedOutfit = _outfit;
        _hasSaved = profile['saved'] == true;
      });
    } catch (_) {
      if (mounted) setState(() => _error = userErrorMessage);
    }
  }

  void _choose({String? avatar, String? outfit}) {
    if (_busy ||
        ((avatar == null || avatar == _avatar) &&
            (outfit == null || outfit == _outfit))) {
      return;
    }
    setState(() {
      _avatar = avatar ?? _avatar;
      _outfit = outfit ?? _outfit;
      _pending = true;
      _previewFailed = false;
    });
  }

  Future<void> _save() async {
    if (_busy || !_stage.ready.value || _pending || _previewFailed) return;
    final avatar = _avatar, outfit = _outfit;
    setState(() => _busy = true);
    try {
      await AppScope.of(context)
          .api
          .patch('/me/huud-avatar', {'avatarId': avatar, 'outfitId': outfit});
      if (!mounted) return;
      setState(() {
        _savedAvatar = avatar;
        _savedOutfit = outfit;
        _hasSaved = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your Huud avatar is saved.')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save your avatar. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _image(String? path, IconData fallback) => path == null
      ? Icon(fallback, size: 26)
      : Image(
          image: SlayAssets.instance.thumbnail(path) ??
              const AssetImage('assets/images/branding/huud_icon.png'),
          width: 42,
          height: 48,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (_, __, ___) => Icon(fallback, size: 26));
  Widget _choice(
          {required String keyName,
          required String name,
          required bool selected,
          required VoidCallback onTap,
          required Widget icon}) =>
      Semantics(
          button: true,
          selected: selected,
          child: InkWell(
              key: ValueKey(keyName),
              onTap: _busy ? null : onTap,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xffe4efdf)
                          : context.neon.panel,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: selected
                              ? const Color(0xff55785f)
                              : context.neon.line,
                          width: selected ? 2 : 1)),
                  child: Row(children: [
                    SizedBox(width: 42, height: 48, child: icon),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(name,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w800))),
                    if (selected)
                      const Icon(Icons.check_circle_rounded,
                          size: 18, color: Color(0xff55785f))
                  ]))));
  @override
  Widget build(BuildContext context) {
    final options = _options, catalog = _catalog;
    final look = options?.look(_avatar, _outfit);
    final unchanged =
        _hasSaved && _avatar == _savedAvatar && _outfit == _savedOutfit;
    return Scaffold(
        appBar: AppBar(title: const Text('Huud avatar')),
        body: SafeArea(
            child: options == null || catalog == null || look == null
                ? Center(
                    child: _error != null
                        ? Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(_error!),
                            TextButton(
                                onPressed: _load, child: const Text('Retry'))
                          ])
                        : const CircularProgressIndicator())
                : Column(children: [
                    SizedBox(
                        height: (MediaQuery.sizeOf(context).height * .33)
                            .clamp(210.0, 320.0),
                        child: SlayStage(
                            catalog: catalog,
                            look: look,
                            controller: _stage,
                            onLoadFailed: (_, __) {
                              if (mounted) {
                                setState(() {
                                  _previewFailed = true;
                                  _pending = true;
                                });
                              }
                            })),
                    Expanded(
                        child: ListView(
                            key: const ValueKey('huud-avatar-options'),
                            padding: const EdgeInsets.all(16),
                            children: [
                          const Text('Your avatar in The Huud',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 5),
                          const Text(
                              'Choose a character and an outfit. Save it to use in your Huuds.'),
                          const SizedBox(height: 16),
                          const Text('AVATARS · 5',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1)),
                          const SizedBox(height: 8),
                          LayoutBuilder(
                              builder: (context, c) =>
                                  Wrap(spacing: 8, runSpacing: 8, children: [
                                    for (final a in options.avatars)
                                      SizedBox(
                                          width: (c.maxWidth - 8) / 2,
                                          child: _choice(
                                              keyName: 'huud-avatar-${a.id}',
                                              name: a.name,
                                              selected: a.id == _avatar,
                                              onTap: () =>
                                                  _choose(avatar: a.id),
                                              icon: _image(
                                                  a.thumbnailUrl,
                                                  a.body == 'female'
                                                      ? Icons.face_3_rounded
                                                      : Icons.face_rounded)))
                                  ])),
                          const SizedBox(height: 20),
                          const Text('OUTFITS · 10',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1)),
                          const SizedBox(height: 8),
                          LayoutBuilder(
                              builder: (context, c) =>
                                  Wrap(spacing: 8, runSpacing: 8, children: [
                                    for (final o in options.outfits)
                                      SizedBox(
                                          width: (c.maxWidth - 8) / 2,
                                          child: _choice(
                                              keyName: 'huud-outfit-${o.id}',
                                              name: o.name,
                                              selected: o.id == _outfit,
                                              onTap: () =>
                                                  _choose(outfit: o.id),
                                              icon: Container(
                                                  margin:
                                                      const EdgeInsets.all(7),
                                                  decoration: BoxDecoration(
                                                      color: Color(int.parse(
                                                          o.swatch.replaceFirst(
                                                              '#', 'ff'),
                                                          radix: 16)),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10)),
                                                  child: const Icon(
                                                      Icons.checkroom_rounded,
                                                      color: Colors.white,
                                                      size: 22))))
                                  ])),
                          if (_previewFailed)
                            const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: Text(
                                    'This outfit could not load. Choose another outfit or retry the preview.')),
                        ])),
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                                key: const ValueKey('huud-avatar-save'),
                                onPressed: _busy ||
                                        _pending ||
                                        _previewFailed ||
                                        unchanged
                                    ? null
                                    : _save,
                                icon: _busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : Icon(unchanged
                                        ? Icons.check_rounded
                                        : Icons.save_rounded),
                                label: Text(_busy
                                    ? 'Saving…'
                                    : unchanged
                                        ? 'Saved'
                                        : 'Save avatar')))),
                  ])));
  }
}
