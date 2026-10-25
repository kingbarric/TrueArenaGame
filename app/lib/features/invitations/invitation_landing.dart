import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/invitation.dart';
import '../draughts/championships_screen.dart';
import '../huudspace/huud_space_models.dart';
import '../huudspace/huud_space_screen.dart';
import '../onboarding/welcome_screen.dart';
import 'invitation_share.dart';

Future<void> rememberInvitation(AppState app, Invitation invitation) async {
  app.pendingHuudCode =
      invitation.kind == InvitationKind.huud ? invitation.code : null;
  app.pendingChampionshipCode =
      invitation.kind == InvitationKind.championship ? invitation.code : null;
  await PendingInvitation.save(invitation);
}

Future<void> clearInvitation(AppState app, {bool refresh = false}) =>
    app.clearPendingInvitation(refresh: refresh);

Future<bool> consumeApplicationInvitation(BuildContext context) async {
  final app = AppScope.of(context);
  if (app.identity == Identity.anonymous ||
      app.activeInvitation != null ||
      ModalRoute.of(context)?.isCurrent != true) {
    return false;
  }
  final invitation = app.pendingChampionshipCode != null
      ? Invitation(InvitationKind.championship, app.pendingChampionshipCode!)
      : app.pendingHuudCode != null
          ? Invitation(InvitationKind.huud, app.pendingHuudCode!)
          : await PendingInvitation.load();
  if (invitation == null || !context.mounted) return false;
  Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => InvitationLanding(invitation: invitation)));
  return true;
}

class InvitationLanding extends StatefulWidget {
  const InvitationLanding({super.key, required this.invitation});
  final Invitation invitation;
  @override
  State<InvitationLanding> createState() => _InvitationLandingState();
}

class _InvitationLandingState extends State<InvitationLanding> {
  Map<String, dynamic>? _preview, _authenticated;
  String? _message;
  bool _busy = false, _loaded = false;
  AppState? _app;
  bool get _cup => widget.invitation.kind == InvitationKind.championship;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_app != null) return;
    _app = AppScope.of(context);
    _app!.activeInvitation = widget.invitation;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await rememberInvitation(_app!, widget.invitation);
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    if (_app?.activeInvitation == widget.invitation) {
      _app!.activeInvitation = null;
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final app = _app!;
      final path = _cup
          ? '/championships/invite/${widget.invitation.code}'
          : '/huud-spaces/invite/${widget.invitation.code}';
      final raw = await app.api.get('$path/preview') as Map;
      Map<String, dynamic>? authenticated;
      if (_cup && app.identity != Identity.anonymous) {
        authenticated =
            (await app.api.get(path) as Map).cast<String, dynamic>();
      }
      if (mounted) {
        setState(() {
          _preview = raw.cast<String, dynamic>();
          _authenticated = authenticated;
          _loaded = true;
          _message = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _message = e.status == 404
              ? 'This invitation is no longer available.'
              : 'Could not load the invitation. Check your connection and try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _message = userErrorMessage;
        });
      }
    }
  }

  bool get _joined => ((_authenticated?['participants'] as List?) ?? const [])
      .whereType<Map>()
      .any((p) => p['id'] == _app?.user?.id);
  bool get _stillHandling =>
      mounted &&
      ModalRoute.of(context)?.isCurrent == true &&
      _app?.activeInvitation == widget.invitation;

  Future<void> _accept() async {
    if (_busy) return;
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final app = _app!;
      if (_cup) {
        final data = _joined
            ? {
                'championshipId': _authenticated!['id'],
                'huudSpaceId': _authenticated!['huudSpaceId']
              }
            : (await app.api.post(
                        '/championships/invite/${widget.invitation.code}/accept')
                    as Map)
                .cast<String, dynamic>();
        final huud = data['huudSpaceId'] as String?;
        if (_joined && huud != null) {
          final current = await app.api.get('/huud-spaces/$huud') as Map;
          if (current['championshipId'] != data['championshipId']) {
            if (mounted) {
              setState(() => _message =
                  'This competition has ended. Ask the host for a new invitation.');
            }
            return;
          }
        }
        if (!_stillHandling) return;
        await clearInvitation(app);
        if (!_stillHandling) return;
        navigator.pushReplacement(huud != null
            ? huudRoute(huud, startOnGame: true)
            : MaterialPageRoute(
                builder: (_) => ChampionshipDetailScreen(
                    id: data['championshipId'] as String)));
      } else {
        final raw = await app.api
            .post('/huud-spaces/join', {'code': widget.invitation.code}) as Map;
        final huud = HuudSpace.fromJson(raw.cast<String, dynamic>());
        if (!_stillHandling) return;
        await clearInvitation(app);
        if (_stillHandling) {
          navigator.pushReplacement(huudRoute(huud.id, initial: huud));
        }
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _message = e.diagnosticMessage == 'FINISH_GAME_FIRST'
            ? 'Finish your current game before accepting this invitation.'
            : switch (e.status) {
                404 => 'This invitation is no longer available.',
                403 => 'This invitation is not available to you.',
                409 =>
                  'This competition may be full or registration has closed. Refresh the invitation to check.',
                _ =>
                  'Could not accept the invitation. Check your connection and try again.',
              });
      }
    } catch (_) {
      if (mounted) setState(() => _message = userErrorMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _guest() async {
    var enteredName = '';
    final nickname = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Choose your player name'),
                content: TextField(
                    onChanged: (value) => enteredName = value,
                    autofocus: true,
                    maxLength: 24,
                    decoration:
                        const InputDecoration(labelText: 'Player name')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () {
                        if (enteredName.trim().isNotEmpty) {
                          Navigator.pop(c, enteredName.trim());
                        }
                      },
                      child: const Text('Continue as guest'))
                ]));
    if (nickname == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _app!.startGuest(nickname);
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        setState(() =>
            _message = 'Could not start your guest session. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = _app!;
    final preview = _preview;
    final name = preview?['name'] as String? ??
        (_cup ? 'Championship invitation' : 'Huud invitation');
    final game = preview?['gameType'] as String?;
    final closed = _cup && preview != null && preview['status'] != 'lobby';
    final full = _cup &&
        preview?['joined'] is num &&
        preview?['size'] is num &&
        (preview!['joined'] as num) >= (preview['size'] as num);
    return Scaffold(
        appBar: AppBar(title: const Text('Your invitation')),
        body: SafeArea(
            child: Center(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Image.asset(
                              'assets/images/branding/playhuud-wordmark-transparent.png',
                              height: 58),
                          const SizedBox(height: 24),
                          if (game != null)
                            Image.asset(invitationGameAsset(game), height: 140),
                          const SizedBox(height: 16),
                          Text(name,
                              textAlign: TextAlign.center,
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 12),
                          Text(
                              _cup
                                  ? '${invitationGameNames[game] ?? 'Game'} championship · ${preview?['joined'] ?? 0}/${preview?['size'] ?? '?'} players'
                                  : 'Good games. Better company.',
                              textAlign: TextAlign.center),
                          const SizedBox(height: 20),
                          if (!_loaded)
                            const Center(child: CircularProgressIndicator()),
                          if (_message != null) ...[
                            Text(_message!, textAlign: TextAlign.center),
                            TextButton(
                                onPressed: _load,
                                child: const Text('Refresh invitation'))
                          ],
                          if (preview != null && (closed || full) && !_joined)
                            Text(
                                closed
                                    ? 'Registration has closed.'
                                    : 'All places are taken.',
                                textAlign: TextAlign.center),
                          if (preview != null &&
                              (closed || full) &&
                              !_joined &&
                              app.identity == Identity.anonymous)
                            OutlinedButton(
                                key: const ValueKey('invite-sign-in'),
                                onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => const WelcomeScreen())),
                                child:
                                    const Text('Already registered? Sign in')),
                          if (preview != null &&
                              (!closed && !full || _joined)) ...[
                            if (app.identity == Identity.anonymous) ...[
                              FilledButton(
                                  key: const ValueKey('invite-guest'),
                                  onPressed: _busy ? null : _guest,
                                  child: const Text('Continue as guest')),
                              OutlinedButton(
                                  key: const ValueKey('invite-sign-in'),
                                  onPressed: _busy
                                      ? null
                                      : () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  const WelcomeScreen())),
                                  child: const Text('Register or sign in')),
                              const Text(
                                  'You can play as a guest and register later.',
                                  textAlign: TextAlign.center),
                            ] else
                              FilledButton(
                                  key: const ValueKey('invite-accept'),
                                  onPressed: _busy ? null : _accept,
                                  child: Text(_busy
                                      ? 'Opening…'
                                      : _joined
                                          ? 'Open competition'
                                          : 'Accept invitation')),
                          ],
                          const SizedBox(height: 16),
                          TextButton(
                              onPressed: () async {
                                final nav = Navigator.of(context);
                                final canPop = nav.canPop();
                                await clearInvitation(app, refresh: !canPop);
                                if (canPop && context.mounted) nav.pop();
                              },
                              child: const Text('Not now')),
                        ])))));
  }
}
