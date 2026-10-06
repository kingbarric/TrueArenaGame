import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../shell/main_shell.dart';
import 'competitive_api.dart';
import 'competitive_models.dart';

/// Where you compete: country, state, optional city.
///
/// Shown once right after registration (with [onboarding] true, skippable so
/// sign-up never gets harder) and reachable from the profile afterwards. Your
/// location only decides which boards you appear on — the rating is the same
/// number on every one of them.
class CompetitiveSetupScreen extends StatefulWidget {
  const CompetitiveSetupScreen({super.key, this.onboarding = false, this.initial});

  final bool onboarding;
  final CompetitiveProfile? initial;

  @override
  State<CompetitiveSetupScreen> createState() => _CompetitiveSetupScreenState();
}

class _CompetitiveSetupScreenState extends State<CompetitiveSetupScreen> {
  late final CompetitiveApi _api = CompetitiveApi(AppScope.of(context).api);

  List<CountryOption> _countries = const [];
  List<RegionOption> _regions = const [];
  CountryOption? _country;
  RegionOption? _region;
  final _freeRegion = TextEditingController();
  final _city = TextEditingController();
  bool _cityPublic = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _freeRegion.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final countries = await _api.countries();
      final loc = widget.initial?.location;
      CountryOption? country;
      if (loc?.countryCode != null) {
        country = countries.where((c) => c.code == loc!.countryCode).firstOrNull;
      }
      _city.text = loc?.city ?? '';
      _cityPublic = loc?.cityPublic ?? false;
      if (!mounted) return;
      setState(() {
        _countries = countries;
        _country = country;
        _loading = false;
      });
      if (country != null) await _loadRegions(country, selectedCode: loc?.regionCode, freeName: loc?.regionName);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load countries — check your connection';
        });
      }
    }
  }

  Future<void> _loadRegions(CountryOption country, {String? selectedCode, String? freeName}) async {
    List<RegionOption> regions = const [];
    if (country.catalogued) {
      try {
        regions = await _api.regions(country.code);
      } catch (_) {/* falls back to free text */}
    }
    if (!mounted) return;
    setState(() {
      _regions = regions;
      _region = regions.where((r) => r.code == selectedCode).firstOrNull;
      _freeRegion.text = regions.isEmpty ? (freeName ?? '') : '';
    });
  }

  bool get _locked {
    final until = widget.initial?.locationLockedUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<CountryOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.neon.panel,
      builder: (_) => _SearchSheet<CountryOption>(
        title: 'COUNTRY',
        items: _countries,
        label: (c) => c.name,
        // The likeliest picks first, then everything else alphabetically.
        pinned: _countries.where((c) => const ['NG', 'GH', 'KE', 'ZA', 'GB', 'US'].contains(c.code)).toList(),
      ),
    );
    if (picked == null || picked.code == _country?.code) return;
    setState(() {
      _country = picked;
      _region = null;
      _regions = const [];
    });
    await _loadRegions(picked);
  }

  Future<void> _pickRegion() async {
    final picked = await showModalBottomSheet<RegionOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.neon.panel,
      builder: (_) => _SearchSheet<RegionOption>(title: 'STATE / REGION', items: _regions, label: (r) => r.name),
    );
    if (picked != null) setState(() => _region = picked);
  }

  Future<void> _save() async {
    final country = _country;
    if (country == null) {
      setState(() => _error = 'Choose your country');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final freeRegion = _freeRegion.text.trim();
      await _api.updateLocation(
        countryCode: country.code,
        regionCode: _regions.isNotEmpty ? _region?.code : null,
        regionName: _regions.isEmpty && freeRegion.isNotEmpty ? freeRegion : null,
        city: _city.text.trim(),
        cityPublic: _cityPublic,
      );
      _finish(saved: true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save — try again');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _finish({required bool saved}) {
    if (!mounted) return;
    if (widget.onboarding) {
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const MainShell()), (r) => false);
    } else {
      Navigator.of(context).pop(saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final t = Theme.of(context).textTheme;
    final hasRegions = _regions.isNotEmpty;
    return Scaffold(
      appBar: widget.onboarding ? null : AppBar(title: const Text('Player profile')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(22), children: [
                if (widget.onboarding) ...[
                  const SizedBox(height: 12),
                  const Text('🏆', style: TextStyle(fontSize: 46), textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  Text('Where do you compete?', style: t.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                ],
                Text(
                  'Your country and state decide which national and state rankings you appear on. '
                  'Your skill rating is the same on every board.',
                  style: t.bodySmall?.copyWith(color: n.mid, height: 1.4),
                ),
                const SizedBox(height: 20),
                if (_locked)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: NeonCard(
                      accent: n.brand,
                      child: Text(
                        'Your ranking location was changed recently. You can change it again after '
                        '${_date(widget.initial!.locationLockedUntil!)}. City can be changed any time.',
                        style: t.labelSmall?.copyWith(color: n.mid, height: 1.4),
                      ),
                    ),
                  ),
                const _FieldLabel('COUNTRY'),
                _PickerField(
                  key: const ValueKey('competitive-country'),
                  value: _country?.name,
                  placeholder: 'Choose your country',
                  onTap: _locked ? null : _pickCountry,
                ),
                const SizedBox(height: 16),
                const _FieldLabel('STATE / REGION'),
                if (_country == null)
                  const _PickerField(value: null, placeholder: 'Choose a country first', onTap: null)
                else if (hasRegions)
                  _PickerField(
                    key: const ValueKey('competitive-region'),
                    value: _region?.name,
                    placeholder: 'Choose your state',
                    onTap: _locked ? null : _pickRegion,
                  )
                else
                  TextField(
                    controller: _freeRegion,
                    enabled: !_locked,
                    maxLength: 60,
                    decoration: const InputDecoration(hintText: 'Your state, province or region', counterText: ''),
                  ),
                const SizedBox(height: 6),
                Text('Needed for state rankings.', style: t.labelSmall?.copyWith(color: n.mute)),
                const SizedBox(height: 16),
                const _FieldLabel('CITY (OPTIONAL)'),
                TextField(
                  controller: _city,
                  maxLength: 60,
                  decoration: const InputDecoration(hintText: 'e.g. Port Harcourt', counterText: ''),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _cityPublic,
                  onChanged: (v) => setState(() => _cityPublic = v),
                  title: Text('Show my city on my public profile', style: t.bodySmall),
                  subtitle: Text('Off by default — only your country and state are public.',
                      style: t.labelSmall?.copyWith(color: n.mute)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose carefully: you can correct your location once, then changes are limited '
                  'to once every 30 days so nobody can hop into an easier ranking.',
                  style: t.labelSmall?.copyWith(color: n.mute, height: 1.4),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: n.danger, fontSize: 12)),
                ],
                const SizedBox(height: 20),
                NeonButton(_saving ? 'Saving…' : (widget.onboarding ? 'Save & continue' : 'Save'),
                    onPressed: _saving ? null : _save),
                if (widget.onboarding) ...[
                  const SizedBox(height: 10),
                  NeonButton('Skip for now',
                      style: NeonStyle.ghost, onPressed: _saving ? null : () => _finish(saved: false)),
                  const SizedBox(height: 8),
                  Text('You can still play and get a global rating. Add your location later from your profile.',
                      textAlign: TextAlign.center, style: t.labelSmall?.copyWith(color: n.mute)),
                ],
              ]),
      ),
    );
  }

  static String _date(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final local = d.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                color: context.neon.gold, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1.2)),
      );
}

class _PickerField extends StatelessWidget {
  const _PickerField({super.key, required this.value, required this.placeholder, required this.onTap});

  final String? value;
  final String placeholder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return NeonCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(children: [
        Expanded(
          child: Text(value ?? placeholder,
              style: TextStyle(
                  color: value == null ? n.mute : (onTap == null ? n.mid : n.ink),
                  fontWeight: value == null ? FontWeight.w500 : FontWeight.w700)),
        ),
        Icon(Icons.expand_more_rounded, color: onTap == null ? n.line : n.mute),
      ]),
    );
  }
}

/// A searchable single-choice list in a bottom sheet.
class _SearchSheet<T> extends StatefulWidget {
  const _SearchSheet({required this.title, required this.items, required this.label, this.pinned = const []});

  final String title;
  final List<T> items;
  final String Function(T) label;
  final List<T> pinned;

  @override
  State<_SearchSheet<T>> createState() => _SearchSheetState<T>();
}

class _SearchSheetState<T> extends State<_SearchSheet<T>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final q = _q.trim().toLowerCase();
    final matches = q.isEmpty
        ? [...widget.pinned, ...widget.items.where((i) => !widget.pinned.contains(i))]
        : widget.items.where((i) => widget.label(i).toLowerCase().contains(q)).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.viewInsetsOf(context).bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.title, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: n.gold)),
            const SizedBox(height: 10),
            TextField(
              autofocus: widget.items.length > 20,
              decoration: const InputDecoration(hintText: 'Search', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: matches.length,
                separatorBuilder: (_, i) => q.isEmpty && widget.pinned.isNotEmpty && i == widget.pinned.length - 1
                    ? Divider(color: n.line)
                    : const SizedBox.shrink(),
                itemBuilder: (_, i) => ListTile(
                  dense: true,
                  title: Text(widget.label(matches[i])),
                  onTap: () => Navigator.of(context).pop(matches[i]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
