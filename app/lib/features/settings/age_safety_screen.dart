import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../core/api_client.dart';
import '../../core/app_state.dart';
import 'delete_account_screen.dart';

/// The server owns rollout and access decisions. No age is cached on the device.
class AgeSafetyGate extends StatefulWidget {
  const AgeSafetyGate({super.key, required this.state, required this.child,
    this.enabled = const bool.fromEnvironment('AGE_SAFETY_GATE_ENABLED')});
  final AppState state;
  final Widget child;
  final bool enabled;
  @override
  State<AgeSafetyGate> createState() => _AgeSafetyGateState();
}

class _AgeSafetyGateState extends State<AgeSafetyGate> {
  String? _subject;
  Map<String, dynamic>? _status;
  bool _failed = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(AgeSafetyGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_subject != widget.state.user?.id || oldWidget.enabled != widget.enabled) _refresh();
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    _subject = widget.state.user?.id;
    _status = null;
    _failed = false;
    if (!widget.enabled || widget.state.identity == Identity.anonymous) return;
    try {
      final result = await widget.state.api.get('/me/age-safety');
      if (!mounted || generation != _generation) return;
      setState(() => _status = Map<String, dynamic>.from(result as Map));
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.state.identity == Identity.anonymous) return widget.child;
    if (_status == null) {
      return Scaffold(
          body: SafeArea(
              child: Center(
                  child: _failed
                      ? Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('We could not check your age settings.'),
                          TextButton(
                              onPressed: () {
                                setState(() => _failed = false);
                                _refresh();
                              },
                              child: const Text('Try again')),
                          TextButton(
                              onPressed: () => widget.state.signOut(),
                              child: const Text('Sign out')),
                        ])
                      : const CircularProgressIndicator())));
    }
    if (_status!['canAccess'] == true) return widget.child;
    // Keep resumed games, invite routes and incoming-call overlays unmounted
    // while access is restricted. A local navigator keeps deletion reachable.
    return Navigator(
        onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => AgeSafetyScreen(
                initial: _status,
                onSaved: (status) => setState(() => _status = status))));
  }
}

class AgeSafetyScreen extends StatefulWidget {
  const AgeSafetyScreen({super.key, this.initial, this.onSaved});
  final Map<String, dynamic>? initial;
  final ValueChanged<Map<String, dynamic>>? onSaved;
  @override
  State<AgeSafetyScreen> createState() => _AgeSafetyScreenState();
}

class _AgeSafetyScreenState extends State<AgeSafetyScreen> {
  String? _country;
  Map<String, dynamic>? _status;
  String? _band;
  bool _acknowledged = false, _busy = false, _failed = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _status = widget.initial;
    if (_status == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final result = await AppScope.of(context).api.get('/me/age-safety');
      if (mounted) {
        setState(() => _status = Map<String, dynamic>.from(result as Map));
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _save() async {
    if (_busy || _band == null || !_acknowledged || _country == null) return;
    final app = AppScope.of(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await app.api.put('/me/age-safety', {
        'ageBand': _band,
        'countryCode': _country,
        'noticeAcknowledged': true,
      });
      if (!mounted) return;
      final status = Map<String, dynamic>.from(result as Map);
      setState(() => _status = status);
      widget.onSaved?.call(status);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _message = error.status == 409
            ? 'These details are already saved. Contact support to request a correction.'
            : 'Could not save. Check your details and try again.');
      }
    } catch (_) {
      if (mounted) setState(() => _message = userRetryMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _privacy() async {
    try {
      await ChromeSafariBrowser()
          .open(url: WebUri('https://playhuud.com/privacy/'));
    } catch (_) {
      if (mounted) {
        setState(() =>
            _message = 'Read our privacy notice at playhuud.com/privacy/');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final declared = status?['ageBand'] != null;
    final restricted =
        status?['enforced'] == true && status?['canAccess'] != true;
    return Scaffold(
        appBar: AppBar(title: const Text('Age and privacy')),
        body: SafeArea(
            child: status == null
                ? Center(
                    child: _failed
                        ? TextButton(
                            onPressed: _load, child: const Text('Try again'))
                        : const CircularProgressIndicator())
                : ListView(padding: const EdgeInsets.all(24), children: [
                    const Text('Your age settings',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Text(
                        'PlayHuud currently requires users to be at least ${status['minimumAge'] ?? 18} where age checks are enabled. Teen access is being prepared and is not enabled by this form.'),
                    const SizedBox(height: 12),
                    const Text(
                        'We store your age range and country privately, not your date of birth. These are self-declared details, not identity verification or parental consent. They are not added to your public profile.'),
                    const SizedBox(height: 12),
                    if (!declared) ...[
                      DropdownButtonFormField<String>(
                          decoration:
                              const InputDecoration(labelText: 'Age range'),
                          items: const [
                            DropdownMenuItem(
                                value: 'UNDER_13', child: Text('Under 13')),
                            DropdownMenuItem(
                                value: 'AGE_13_15', child: Text('13–15')),
                            DropdownMenuItem(
                                value: 'AGE_16_17', child: Text('16–17')),
                            DropdownMenuItem(
                                value: 'ADULT', child: Text('18 or older')),
                          ],
                          onChanged:
                              _busy ? null : (v) => setState(() => _band = v)),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Country where you live'),
                          items: [
                            for (final country
                                in (status['countries'] as List? ?? const []))
                              DropdownMenuItem(
                                  value: country['code'] as String,
                                  child: Text(country['name'] as String,
                                      overflow: TextOverflow.ellipsis))
                          ],
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _country = v)),
                      CheckboxListTile(
                          value: _acknowledged,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                              'I understand how these private age details are used.'),
                          onChanged: _busy
                              ? null
                              : (v) =>
                                  setState(() => _acknowledged = v ?? false)),
                      FilledButton(
                          onPressed: _busy ||
                                  _band == null ||
                                  !_acknowledged ||
                                  _country == null
                              ? null
                              : _save,
                          child: Text(_busy ? 'Saving…' : 'Save age details')),
                    ] else ...[
                      Text('Age range: ${{
                            'UNDER_13': 'Under 13',
                            'AGE_13_15': '13–15',
                            'AGE_16_17': '16–17',
                            'ADULT': '18 or older'
                          }[status['ageBand']] ?? 'Not set'}'),
                      Text('Country: ${status['countryCode']}'),
                      const SizedBox(height: 12),
                      const Text(
                          'To request a correction, contact support. Age details cannot be changed here to bypass an age restriction.'),
                    ],
                    if (restricted && declared) ...[
                      const SizedBox(height: 16),
                      Text(status['restriction'] == 'BELOW_MINIMUM_AGE'
                          ? 'Your declared age does not meet the current minimum age.'
                          : 'Teen access is not available yet. Your public, chat and voice access is restricted.'),
                    ],
                    if (status['enforced'] != true)
                      const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: Text(
                              'Age enforcement has not been activated. Saving details does not enable a teen mode or change your communication settings.')),
                    TextButton(
                        onPressed: _privacy,
                        child: const Text('Read privacy notice')),
                    const SelectableText('Support: kingbarric@yahoo.com'),
                    if (_message != null)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(_message!)),
                    if (restricted) ...[
                      TextButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const DeleteAccountScreen())),
                          child: const Text('Delete account')),
                      TextButton(
                          onPressed: () => AppScope.of(context).signOut(),
                          child: const Text('Sign out')),
                    ],
                  ])));
  }
}
