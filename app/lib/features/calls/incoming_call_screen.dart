import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../core/app_state.dart';
import '../../core/hangout_state.dart';
import '../../core/call_ringer.dart';
import '../../core/e2e_crypto.dart';
import '../../widgets/neon.dart';
import 'call_screen.dart';

/// Shows a ringing screen whenever a friend calls, wherever you are in the
/// app. Fed by the inbox socket (`CALL_INCOMING` / `CALL_CANCELLED`) while
/// the app is open, and by tapping a call push when it wasn't. Also buzzes
/// the phone when a friend nudges you.
class IncomingCalls {
  IncomingCalls._();

  static StreamSubscription? _sub;
  static String? _ringingFrom;

  /// Starts listening on the app's inbox. Safe to call more than once.
  static void attach(AppState app) {
    _sub?.cancel();
    _sub = app.callEvents.listen((event) {
      final type = event['type'];
      final data =
          ((event['data'] as Map?) ?? const {}).cast<String, dynamic>();
      if (type == 'CALL_INCOMING') {
        present(data);
      } else if (type == 'CALL_CANCELLED') {
        if (data['callerId'] == _ringingFrom) _missed?.call();
      } else if (type == 'VOICE_JOIN_ANSWERED' && data['approved'] == true) {
        final ctx = TrueArenaApp.navigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: const Text('Your hangout join request was approved'),
          action: SnackBarAction(
              label: 'Join',
              onPressed: () async {
                try {
                  final path = '/calls/rooms/${data['roomName']}/token';
                  final token =
                      await app.api.post(path) as Map<String, dynamic>;
                  if (!ctx.mounted) return;
                  await CallScreen.open(
                      ctx,
                      CallScreen(
                          roomName: token['roomName'] as String,
                          token: token['token'] as String,
                          livekitUrl: token['livekitUrl'] as String,
                          title: 'Huud hangout',
                          refreshToken: () async => ((await app.api.post(path)
                              as Map<String, dynamic>)['token'] as String)));
                } catch (_) {
                  if (ctx.mounted)
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text('Could not join the hangout')));
                }
              }),
        ));
      } else if (type == 'NUDGE') {
        nudged(data['fromName'] as String? ?? 'A friend');
      }
    });
  }

  static VoidCallback? _missed;

  /// A friend wants you online: two buzzes and a note saying who.
  static void nudged(String fromName) {
    HapticFeedback.vibrate();
    Future.delayed(const Duration(milliseconds: 450), HapticFeedback.vibrate);
    final ctx = TrueArenaApp.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(
      content: Text('👋 $fromName nudged you — they want you to play!'),
      duration: const Duration(seconds: 4),
    ));
  }

  /// Opens the ringing screen for a call, unless one is already ringing or
  /// you're already on a call.
  static void present(Map<String, dynamic> data) {
    final callerId = data['callerId'] as String?;
    if (callerId == null || _ringingFrom != null) return;
    final nav = TrueArenaApp.navigatorKey.currentState;
    if (nav == null) return;
    if (HangoutState.instance.active) HangoutState.instance.minimize();
    _ringingFrom = callerId;
    nav
        .push(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => IncomingCallScreen(
                  callerId: callerId,
                  roomName: data['roomName'] as String?,
                  callerName: data['callerName'] as String? ?? 'A friend',
                  callerAvatar: data['callerAvatar'] as String?,
                  callerPublicKey: data['callerPublicKey'] as String?,
                  sealedMediaKey: data['mediaKey'] as String?,
                )))
        .whenComplete(() {
      _ringingFrom = null;
      _missed = null;
    });
  }
}

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({
    super.key,
    required this.callerId,
    required this.callerName,
    this.roomName,
    this.callerAvatar,
    this.callerPublicKey,
    this.sealedMediaKey,
  });

  final String callerId;
  final String callerName;

  /// The call room to join on Accept. Absent only on an old push, which
  /// means the caller's own 1:1 room.
  final String? roomName;
  final String? callerAvatar;
  final String? callerPublicKey;

  /// When someone adds you to an encrypted 1:1 call: its media key, sealed
  /// to you with the key you share with them.
  final String? sealedMediaKey;

  /// How long a call rings before it counts as missed.
  static const ringFor = Duration(seconds: 45);

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();
  Timer? _timeout;
  bool _answering = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    CallRinger.ring();
    IncomingCalls._missed = () => _end('Missed call');
    _timeout = Timer(IncomingCallScreen.ringFor, () => _end('Missed call'));
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _pulse.dispose();
    CallRinger.stop();
    super.dispose();
  }

  void _end(String status) {
    if (!mounted || _answering) return;
    CallRinger.stop();
    _timeout?.cancel();
    setState(() => _status = status);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _decline() async {
    CallRinger.stop();
    final app = AppScope.of(context);
    app.api
        .post('/calls/dm/${widget.callerId}/decline')
        .catchError((_) => null);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _accept() async {
    if (_answering) return;
    setState(() => _answering = true);
    await CallRinger.stop();
    _timeout?.cancel();
    if (!mounted) return;
    final app = AppScope.of(context);
    final path = widget.roomName == null
        ? '/calls/dm/${widget.callerId}/token'
        : '/calls/rooms/${widget.roomName}/token';
    try {
      final res = await app.api.post(path) as Map<String, dynamic>;
      String? mediaKeyHex;
      final sealed = widget.sealedMediaKey;
      if (sealed != null) {
        final secret = await E2eCrypto.sharedSecretWith(widget.callerPublicKey);
        if (secret != null)
          mediaKeyHex = await E2eCrypto.decrypt(secret, sealed);
      }
      if (!mounted) return;
      await CallScreen.open(
          context,
          CallScreen(
            roomName: res['roomName'] as String,
            token: res['token'] as String,
            livekitUrl: res['livekitUrl'] as String,
            title: widget.callerName,
            // Joining someone else's 1:1 uses the key they sealed for us; a
            // plain 1:1 derives it from the caller's public key.
            peerPublicKey: sealed == null ? widget.callerPublicKey : null,
            mediaKeyHex: mediaKeyHex,
            refreshToken: () async => ((await app.api.post(path)
                as Map<String, dynamic>)['token'] as String),
          ));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _answering = false;
        _status = 'Could not connect the call';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xff120a1e);
    const cream = Color(0xfffff1dc);
    const mute = Color(0xffa894c4);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _decline();
      },
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Column(children: [
            const SizedBox(height: 56),
            const Text('PLAYHUUD VOICE CALL',
                style: TextStyle(
                    color: mute,
                    fontSize: 12,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 36),
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) =>
                  Stack(alignment: Alignment.center, children: [
                for (final offset in [0.0, 0.5])
                  Builder(builder: (_) {
                    final t = (_pulse.value + offset) % 1.0;
                    return Container(
                      width: 130 + 90 * t,
                      height: 130 + 90 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xff3ddc84)
                                .withValues(alpha: (1 - t) * 0.5),
                            width: 2),
                      ),
                    );
                  }),
                child!,
              ]),
              child: Avatar(widget.callerName,
                  size: 120, imageUrl: widget.callerAvatar),
            ),
            const SizedBox(height: 36),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(widget.callerName,
                  key: const ValueKey('incoming-caller'),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(
                      color: cream, fontSize: 28, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 8),
            Text(_status ?? (_answering ? 'Connecting…' : 'is calling you…'),
                style: const TextStyle(color: mute, fontSize: 15)),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 40, 48),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _action(
                      key: const ValueKey('incoming-decline'),
                      icon: Icons.call_end_rounded,
                      color: const Color(0xffe5484d),
                      label: 'Decline',
                      onTap: _status != null ? null : _decline,
                    ),
                    _action(
                      key: const ValueKey('incoming-accept'),
                      icon: Icons.call_rounded,
                      color: const Color(0xff3ddc84),
                      label: 'Accept',
                      onTap: _status != null || _answering ? null : _accept,
                    ),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _action(
      {required Key key,
      required IconData icon,
      required Color color,
      required String label,
      VoidCallback? onTap}) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Material(
        key: key,
        color: onTap == null ? color.withValues(alpha: 0.4) : color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
              width: 74,
              height: 74,
              child: Icon(icon, color: Colors.white, size: 34)),
        ),
      ),
      const SizedBox(height: 10),
      Text(label,
          style: const TextStyle(
              color: Color(0xfffff1dc), fontWeight: FontWeight.w700)),
    ]);
  }
}
