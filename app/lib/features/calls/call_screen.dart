import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/hangout_state.dart';
import '../chess/chess_lobby_screen.dart';
import '../draughts/draughts_lobby_screen.dart';
import '../whot/whot_lobby_screen.dart';
import '../ludo/ludo_lobby_screen.dart';
import '../goosi/goosi_lobby_screen.dart';
import '../wordbluff/wordbluff_lobby_screen.dart';
import '../modes/mode_select_screen.dart';
import '../../core/call_ringer.dart';
import '../../core/e2e_crypto.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';

/// A voice call — 1:1 or group, same screen either way, since a LiveKit
/// room is multi-party by default (see `CallService`, ta-api: a DM call and
/// a group call are the same mechanism, just a different room name and
/// membership check to get the token).
///
/// Beyond talking:
/// - **Ringing.** With [ringPeerId] set, the friend's phone rings once
///   this side is connected, and the caller hears a ringback until they
///   pick up, decline, or 45 seconds pass.
/// - **Staying connected.** LiveKit retries a brief blip on its own. If it
///   gives up, this screen keeps rejoining (with a fresh token from
///   [refreshToken]) until the network comes back, and only ends the call
///   after [giveUpAfter] with no way through.
/// - **Host controls.** The host can mute/remove participants, transfer
///   ownership, or end the hangout. Other participants can leave or locally mute.
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.roomName,
    required this.token,
    required this.livekitUrl,
    required this.title,
    this.peerPublicKey,
    this.mediaKeyHex,
    this.ringPeerId,
    this.refreshToken,
    this.onConnected,
    this.onAskToSpeak,
  });

  final String roomName;
  final String token;
  final String livekitUrl;
  final String title;

  /// The other participant's X25519 public key, for a 1:1 call — when
  /// present, the same shared secret that encrypts this pair's DMs is used
  /// as LiveKit's frame-encryption key, so the media is end-to-end
  /// encrypted and the SFU relays frames it can't decode (see `E2eCrypto`).
  /// Null for a group call, which stays transport-encrypted (DTLS-SRTP).
  final String? peerPublicKey;

  /// The media key itself, when someone added you to an encrypted 1:1 call
  /// and sent it sealed to you — takes the place of deriving it.
  final String? mediaKeyHex;

  /// The friend to ring once connected (an outgoing 1:1 call).
  final String? ringPeerId;

  /// Fetches a new token for this room when rejoining after a drop.
  final Future<String> Function()? refreshToken;
  final Future<void> Function()? onConnected;

  /// For rooms where you listen until someone hands you the mic (a Huud):
  /// tapping the mic without permission asks instead.
  final Future<void> Function()? onAskToSpeak;

  /// True for an app-scoped hangout, including while its screen is minimized.
  static bool get inCall => HangoutState.instance.active;

  static Future<bool> open(BuildContext context, CallScreen next) async {
    final call = HangoutState.instance;
    if (call.active && call.roomName == next.roomName) {
      call.show();
      return true;
    }
    if (call.active) {
      final switchCall = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: const Text('Join another voice session?'),
                content: const Text(
                    'You are currently in another voice session. Leave current call and join this one?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Leave & Join')),
                ],
              ));
      if (switchCall != true) return false;
      await call.leave?.call();
      if (call.active) return false;
      if (!context.mounted) return false;
    }
    call.open(next, next.roomName, next.title);
    return true;
  }

  static const ringFor = Duration(seconds: 45);
  static const giveUpAfter = Duration(minutes: 2);

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _events;
  Timer? _ticker;
  Timer? _heartbeat;
  bool _leavingPrompt = false;
  Timer? _ringTimeout;
  Timer? _peerWait;
  StreamSubscription? _callEvents;

  bool _connecting = true;
  bool _muted = false;

  /// False while the room only lets you listen (a Huud, until the host hands
  /// you the mic). The server flips it live.
  bool _canSpeak = true;
  bool _e2ee = false;
  bool _leaving = false;
  bool _ringing = false;
  bool _reconnecting = false;
  bool _recovering = false;
  String? _error;

  /// Why the call is over, shown briefly before the screen closes.
  String? _ended;
  int _seconds = 0;
  String? _mediaKeyHex;
  final Set<String> _saidGoodbye = {};
  final Set<String> _locallyMuted = {};

  bool _started = false;
  AppState? _app;

  bool get _manageable => true;
  bool get _isHost => HangoutState.instance.ownerId == _app?.user?.id;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _app = AppScope.of(context);
    final call = HangoutState.instance;
    call.leave = _leave;
    call.toggleMute = _toggleMute;
    call.play = _playTogether;
    _callEvents = _app!.callEvents.listen(_onCallEvent);
    _start();
  }

  @override
  void dispose() {
    CallRinger.stop();
    _ticker?.cancel();
    _heartbeat?.cancel();
    _ringTimeout?.cancel();
    _peerWait?.cancel();
    _callEvents?.cancel();
    _teardown();
    super.dispose();
  }

  void _teardown() {
    _events?.dispose();
    _events = null;
    final room = _room;
    _room = null;
    if (room != null && HangoutState.instance.room == room) {
      HangoutState.instance.attach(null);
    }
    if (room != null) {
      room.removeListener(_onRoomChanged);
      room.disconnect();
      room.dispose();
    }
  }

  void _onRoomChanged() {
    if (mounted) setState(() {});
  }

  void _applySession(Map<String, dynamic> session) {
    if (session['roomName'] != widget.roomName) return;
    final call = HangoutState.instance;
    call.session = session;
    call.ownerId = session['ownerId'] as String?;
    for (final raw in (session['participants'] as List? ?? const [])) {
      final participant = (raw as Map).cast<String, dynamic>();
      call.avatars[participant['userId'] as String] =
          participant['avatarUrl'] as String?;
      if (participant['userId'] == _app?.user?.id) {
        call.muted = participant['muted'] == true;
      }
    }
    call.changed();
    if (mounted) setState(() {});
  }

  Future<void> _refreshSession({bool heartbeat = false}) async {
    try {
      if (heartbeat) await _app?.api.post('/calls/sessions/heartbeat');
      final raw = await _app?.api.get('/calls/sessions/active');
      if (mounted && raw is Map) _applySession(raw.cast<String, dynamic>());
    } catch (_) {
      /* Voice reconnect runs independently of the API connection. */
    }
  }

  // ------------------------------------------------------------ joining

  Future<void> _start() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error =
              'Microphone access is off — turn it on in Settings to make calls.';
        });
      }
      return;
    }
    try {
      _mediaKeyHex = widget.mediaKeyHex;
      if (_mediaKeyHex == null) {
        final secret = await E2eCrypto.sharedSecretWith(widget.peerPublicKey);
        if (secret != null) {
          _mediaKeyHex = await E2eCrypto.sharedSecretHex(secret);
        }
      }
      final joined = await _app!.api
          .post('/calls/sessions/join', {'roomName': widget.roomName});
      if (!mounted) return;
      _applySession((joined as Map).cast<String, dynamic>());
      _muted = HangoutState.instance.muted;
      _heartbeat = Timer.periodic(
          const Duration(seconds: 30), (_) => _refreshSession(heartbeat: true));
      await _join(widget.token);
      await widget.onConnected?.call();
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _e2ee = _mediaKeyHex != null;
      });
      if (widget.ringPeerId != null &&
          (_room?.remoteParticipants.isEmpty ?? true)) {
        _startRinging();
      } else {
        _startClock();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error =
              'Could not connect — check your mic permission and connection.';
        });
      }
    }
  }

  /// Connects a fresh room. Used for the first join and every rejoin.
  Future<void> _join(String token) async {
    lk.E2EEOptions? e2ee;
    final keyHex = _mediaKeyHex;
    if (keyHex != null) e2ee = await lk.E2EEOptions.sharedKey(keyHex);
    final room = lk.Room(roomOptions: lk.RoomOptions(e2eeOptions: e2ee));
    _room = room;
    HangoutState.instance.attach(room);
    room.addListener(_onRoomChanged);
    final events = room.createListener();
    _events = events;
    events
      ..on<lk.RoomReconnectingEvent>((_) => _setReconnecting(true))
      ..on<lk.RoomAttemptReconnectEvent>((_) => _setReconnecting(true))
      ..on<lk.RoomReconnectedEvent>((_) => _setReconnecting(false))
      ..on<lk.RoomDisconnectedEvent>((e) => _onDisconnected(e.reason))
      ..on<lk.TrackSubscribedEvent>((e) {
        if (_locallyMuted.contains(e.participant.identity)) {
          e.publication.unsubscribe();
        }
      })
      ..on<lk.ParticipantConnectedEvent>((e) => _onPeerJoined(e.participant))
      ..on<lk.ParticipantDisconnectedEvent>((e) => _onPeerLeft(e.participant))
      ..on<lk.DataReceivedEvent>((e) {
        if (e.topic == 'call' && utf8.decode(e.data) == 'bye') {
          final who = e.participant?.identity;
          if (who != null) _saidGoodbye.add(who);
        }
      })
      ..on<lk.ParticipantPermissionsUpdatedEvent>((e) {
        if (e.participant is! lk.LocalParticipant || !mounted) return;
        final can = e.permissions.canPublish;
        if (can == _canSpeak) return;
        setState(() {
          _canSpeak = can;
          if (!can) _muted = true;
        });
        HangoutState.instance.muted = _muted;
        HangoutState.instance.changed();
        // Granted: still off until they tap it, so nobody is suddenly live.
        _note(can ? 'You can talk now — tap the mic 🎙️' : 'The host turned your mic off');
      })
      ..on<lk.TrackMutedEvent>((e) {
        if (e.participant is lk.LocalParticipant && !_muted && mounted) {
          setState(() => _muted = true);
          HangoutState.instance.muted = true;
          HangoutState.instance.changed();
          _app?.api.post(
              '/calls/sessions/mute', {'muted': true}).catchError((_) => null);
          _note('You were muted — tap the mic to unmute.');
        }
      });
    await room.connect(widget.livekitUrl, token);
    _canSpeak = room.localParticipant?.permissions.canPublish ?? true;
    if (_canSpeak) {
      await room.localParticipant?.setMicrophoneEnabled(!_muted);
    } else {
      _muted = true;
      HangoutState.instance.muted = true;
    }
  }

  void _setReconnecting(bool value) {
    if (mounted && _reconnecting != value) {
      setState(() => _reconnecting = value);
    }
  }

  void _onDisconnected(lk.DisconnectReason? reason) {
    if (_leaving || _ended != null || _recovering) return;
    switch (reason) {
      case lk.DisconnectReason.participantRemoved:
        _finish('You were removed from the call');
      case lk.DisconnectReason.roomDeleted:
      case lk.DisconnectReason.duplicateIdentity:
        _finish('Call ended');
      case lk.DisconnectReason.clientInitiated:
        break;
      default:
        _recover();
    }
  }

  /// LiveKit gave up on its own quick retries — keep trying to rejoin until
  /// the network is back or [CallScreen.giveUpAfter] passes.
  Future<void> _recover() async {
    if (_recovering) return;
    _recovering = true;
    _setReconnecting(true);
    _teardown();
    final deadline = DateTime.now().add(CallScreen.giveUpAfter);
    while (mounted && !_leaving && DateTime.now().isBefore(deadline)) {
      try {
        var token = widget.token;
        final refresh = widget.refreshToken;
        if (refresh != null) {
          try {
            token = await refresh();
          } catch (_) {
            // no network for the token either — try the one we have
          }
        }
        await _join(token);
        _recovering = false;
        _setReconnecting(false);
        return;
      } catch (_) {
        _teardown();
        await Future.delayed(const Duration(seconds: 3));
      }
    }
    _recovering = false;
    if (mounted && !_leaving) _finish('Connection lost');
  }

  // ------------------------------------------------------------ ringing

  void _startRinging() {
    setState(() => _ringing = true);
    CallRinger.ringback();
    _app?.api
        .post('/calls/dm/${widget.ringPeerId}/ring')
        .catchError((_) => null);
    _ringTimeout = Timer(CallScreen.ringFor, () {
      if (!_ringing) return;
      _app?.api
          .post('/calls/dm/${widget.ringPeerId}/cancel')
          .catchError((_) => null);
      _finish('No answer');
    });
  }

  void _stopRinging() {
    if (!_ringing) return;
    _ringTimeout?.cancel();
    CallRinger.stop();
    if (mounted) setState(() => _ringing = false);
  }

  void _onCallEvent(Map<String, dynamic> event) {
    final data = ((event['data'] as Map?) ?? const {}).cast<String, dynamic>();
    if (event['type'] == 'VOICE_ENDED' && data['roomName'] == widget.roomName) {
      _leaving = true;
      HangoutState.instance.clear();
      return;
    }
    if (event['type'] == 'VOICE_USER_LEFT' &&
        data['roomName'] == widget.roomName) {
      _note('A participant left the hangout');
    }
    if (event['type']?.toString().startsWith('VOICE_') == true) {
      _refreshSession();
    }
    if (event['type'] == 'CALL_DECLINED' &&
        _ringing &&
        data['by'] == widget.ringPeerId) {
      _stopRinging();
      _finish('Declined');
    }
  }

  void _startClock() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_reconnecting) setState(() => _seconds++);
    });
  }

  void _onPeerJoined(lk.RemoteParticipant p) {
    _peerWait?.cancel();
    _peerWait = null;
    if (_ringing) _stopRinging();
    _startClock();
    _refreshSession();
    if (mounted) setState(() {});
  }

  /// The other side of a 1:1 left. If they hung up, the call is over; if
  /// they dropped off, give them time to come back.
  void _onPeerLeft(lk.RemoteParticipant p) {
    // A hangout remains available to the people still here.
    if (mounted) setState(() {});
  }

  void _finish(String why) {
    if (!mounted || _ended != null) return;
    CallRinger.stop();
    setState(() => _ended = why);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      if (_isHost &&
          (why == 'No answer' || why == 'Declined') &&
          (_room?.remoteParticipants.isEmpty ?? true)) {
        _app?.api.post('/calls/sessions/end').catchError((_) => null);
      }
      _leaving = true;
      HangoutState.instance.clear();
    });
  }

  // ------------------------------------------------------------ actions

  Future<void> _toggleMute() async {
    if (!_canSpeak) {
      await widget.onAskToSpeak?.call();
      _note(widget.onAskToSpeak == null ? 'You can only listen here' : 'Asked the host for the mic ✋');
      return;
    }
    final next = !_muted;
    await _room?.localParticipant?.setMicrophoneEnabled(!next);
    if (mounted) setState(() => _muted = next);
    HangoutState.instance.muted = next;
    HangoutState.instance.changed();
    try {
      await _app?.api.post('/calls/sessions/mute', {'muted': next});
    } catch (_) {}
  }

  Future<bool> _delegateHost() async {
    await _refreshSession();
    if (!mounted) return false;
    final others =
        ((HangoutState.instance.session?['participants'] as List?) ?? const [])
            .map((p) => (p as Map).cast<String, dynamic>())
            .where((p) => p['userId'] != _app?.user?.id)
            .toList();
    if (!_isHost || others.isEmpty) return true;
    HangoutState.instance.show();
    final next = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.neon.panel,
      showDragHandle: true,
      isScrollControlled: true,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
      builder: (ctx) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
        const ListTile(
            title: Text('Choose the next host'),
            subtitle: Text('The hangout will keep running.')),
        for (final p in others)
          ListTile(
            leading: Avatar(p['displayName'] as String? ?? '?',
                size: 40, imageUrl: p['avatarUrl'] as String?),
            title: Text(p['displayName'] as String? ?? 'Participant'),
            onTap: () => Navigator.of(ctx).pop(p['userId'] as String),
          ),
      ])),
    );
    if (next == null) return false;
    await _app!.api.post('/calls/sessions/delegate', {'userId': next});
    await _refreshSession();
    return true;
  }

  Future<void> _leave() async {
    if (_leaving || _leavingPrompt) return;
    _leavingPrompt = true;
    try {
      if (!await _delegateHost()) return;
      _leaving = true;
      await _app!.api
          .post('/calls/sessions/leave', {'roomName': widget.roomName});
      if (_ringing && widget.ringPeerId != null) {
        await _app!.api.post('/calls/dm/${widget.ringPeerId}/cancel');
      }
      await CallRinger.stop();
      await _room?.disconnect();
      HangoutState.instance.clear();
    } catch (error) {
      _leaving = false;
      _note(error is ApiException
          ? error.message
          : 'Could not leave. Check your connection and try again.');
    } finally {
      _leavingPrompt = false;
    }
  }

  Future<void> _endForEveryone() async {
    try {
      _leaving = true;
      await _app!.api.post('/calls/sessions/end');
      await _room?.disconnect();
      HangoutState.instance.clear();
    } catch (error) {
      _leaving = false;
      _note(error is ApiException ? error.message : 'Could not end the call');
    }
  }

  Future<void> _hangoutSettings() async {
    final session = HangoutState.instance.session;
    if (session == null) return;
    var privacy = session['privacy'] as String? ?? 'invite_only';
    var invites = session['invitePermissions'] as String? ?? 'participants';
    await showModalBottomSheet<void>(
        context: context,
        backgroundColor: context.neon.panel,
        showDragHandle: true,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const ListTile(title: Text('Hangout settings')),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: DropdownButtonFormField<String>(
                          initialValue: privacy,
                          decoration: const InputDecoration(
                              labelText: 'Who can request to join?'),
                          items: [
                            for (final p in [
                              'public',
                              'friends',
                              'invite_only',
                              'private'
                            ])
                              if (session['type'] != 'direct' ||
                                  p == 'invite_only' ||
                                  p == 'private')
                                DropdownMenuItem(
                                    value: p,
                                    child: Text(p.replaceAll('_', ' ')))
                          ],
                          onChanged: (p) => update(() => privacy = p!),
                        )),
                    SwitchListTile(
                        title: const Text('Participants can invite friends'),
                        value: invites == 'participants',
                        onChanged: (v) => update(
                            () => invites = v ? 'participants' : 'host')),
                    FilledButton(
                        onPressed: () async {
                          try {
                            await _app!.api.post('/calls/sessions/settings', {
                              'privacy': privacy,
                              'invitePermissions': invites
                            });
                            await _refreshSession();
                            if (ctx.mounted) Navigator.of(ctx).pop();
                          } catch (_) {
                            _note('Could not save hangout settings');
                          }
                        },
                        child: const Text('Save')),
                    const SizedBox(height: 16),
                  ]),
                )));
  }

  Future<void> _showJoinRequests() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: context.neon.panel,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
      builder: (_) => SafeArea(
          child: ListenableBuilder(
        listenable: HangoutState.instance,
        builder: (ctx, _) => ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Join requests')),
          for (final request
              in (HangoutState.instance.session?['joinRequests'] as List? ??
                  const []))
            ListTile(
                leading: Avatar(request['displayName'] as String? ?? '?',
                    size: 36, imageUrl: request['avatarUrl'] as String?),
                title: Text('${request['displayName']} wants to join'),
                trailing: Wrap(children: [
                  IconButton(
                      tooltip: 'Decline',
                      icon: const Icon(Icons.close),
                      onPressed: () =>
                          _answerJoin(request['userId'] as String, false)),
                  IconButton(
                      tooltip: 'Approve',
                      icon: const Icon(Icons.check),
                      onPressed: () =>
                          _answerJoin(request['userId'] as String, true)),
                ])),
        ]),
      )),
    );
  }

  Future<void> _answerJoin(String userId, bool approved) async {
    try {
      await _app!.api.post(
          '/calls/sessions/requests/$userId/answer', {'approved': approved});
      await _refreshSession();
    } catch (_) {
      _note('Could not answer the join request');
    }
  }

  void _note(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _manage(lk.RemoteParticipant p, String action) async {
    final name = p.name.isNotEmpty ? p.name : 'them';
    try {
      await _app!.api.post(
          '/calls/rooms/${widget.roomName}/participants/${p.identity}/$action');
      _note(action == 'mute' ? 'Muted $name' : 'Dropped $name from the call');
    } on ApiException catch (e) {
      _note(e.message);
    } catch (_) {
      _note('Could not reach the server');
    }
  }

  void _participantMenu(lk.RemoteParticipant p) {
    final name = p.name.isNotEmpty ? p.name : p.identity;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xff241517),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Text(name,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
          const SizedBox(height: 4),
          ListTile(
            leading: const Icon(Icons.volume_off_outlined),
            title: Text(_locallyMuted.contains(p.identity)
                ? 'Listen to $name'
                : 'Mute $name for me'),
            onTap: () async {
              final mute = !_locallyMuted.contains(p.identity);
              for (final track in p.audioTrackPublications) {
                if (mute) {
                  await track.unsubscribe();
                } else {
                  await track.subscribe();
                }
              }
              if (mounted)
                setState(() {
                  if (mute) {
                    _locallyMuted.add(p.identity);
                  } else {
                    _locallyMuted.remove(p.identity);
                  }
                });
              if (sheet.mounted) Navigator.of(sheet).pop();
            },
          ),
          if (_isHost)
            ListTile(
              key: const ValueKey('call-mute-participant'),
              leading: const Icon(Icons.mic_off_rounded, color: Colors.white),
              title: Text('Mute $name',
                  style: const TextStyle(color: Colors.white)),
              subtitle: const Text('They can unmute themselves',
                  style: TextStyle(color: Colors.white54)),
              onTap: () {
                Navigator.of(sheet).pop();
                _manage(p, 'mute');
              },
            ),
          if (_isHost)
            ListTile(
              key: const ValueKey('call-drop-participant'),
              leading: const Icon(Icons.person_remove_rounded,
                  color: Color(0xffe5484d)),
              title: Text('Drop $name from the call',
                  style: const TextStyle(color: Color(0xffe5484d))),
              onTap: () {
                Navigator.of(sheet).pop();
                _manage(p, 'remove');
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _addPerson() async {
    final app = _app!;
    List<Map<String, dynamic>> friends;
    try {
      friends = [
        for (final f in (await app.api.get('/friends') as List))
          (f as Map).cast<String, dynamic>()
      ];
    } catch (_) {
      _note('Could not load your friends');
      return;
    }
    final here = {
      ...?_room?.remoteParticipants.values.map((p) => p.identity),
      app.user?.id,
    };
    friends.removeWhere((f) => here.contains(f['userId']));
    if (!mounted) return;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff241517),
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Add someone to the call',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
          ),
          if (friends.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Text('Everyone you could add is already here.',
                  style: TextStyle(color: Colors.white54)),
            )
          else
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final f in friends)
                  ListTile(
                    leading: Avatar(f['displayName'] as String? ?? '?',
                        size: 36, imageUrl: f['avatarUrl'] as String?),
                    title: Text(f['displayName'] as String? ?? '',
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text('@${f['username'] ?? ''}',
                        style: const TextStyle(color: Colors.white54)),
                    trailing: const Icon(Icons.call_rounded,
                        color: Color(0xff3ddc84)),
                    onTap: () => Navigator.of(sheet).pop(f),
                  ),
              ]),
            ),
        ]),
      ),
    );
    if (picked == null) return;
    final name = picked['displayName'] as String? ?? 'them';
    String? sealedKey;
    final keyHex = _mediaKeyHex;
    if (keyHex != null) {
      // An encrypted call: seal the media key to them so they can hear it.
      final secret =
          await E2eCrypto.sharedSecretWith(picked['publicKey'] as String?);
      if (secret == null) {
        _note("$name's app can't join an encrypted call yet.");
        return;
      }
      sealedKey = await E2eCrypto.encrypt(secret, keyHex);
    }
    try {
      await app.api.post(
          '/calls/rooms/${widget.roomName}/invite/${picked['userId']}',
          {if (sealedKey != null) 'mediaKey': sealedKey});
      _note('Ringing $name…');
    } on ApiException catch (e) {
      _note(e.message);
    } catch (_) {
      _note('Could not reach the server');
    }
  }

  Future<void> _playTogether() async {
    HangoutState.instance.show();
    final choices = <String, Widget>{
      'Chess': const ChessLobbyScreen(),
      'Draughts': const DraughtsLobbyScreen(),
      'Whot': const WhotLobbyScreen(),
      'Ludo': const LudoLobbyScreen(),
      'Mancala': const GoosiLobbyScreen(),
      'Traitors': const ModeSelectScreen(),
      'Word Bluff': const WordBluffLobbyScreen(),
    };
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.neon.panel,
      builder: (ctx) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('Play together')),
        for (final name in choices.keys)
          ListTile(
            leading: const Icon(Icons.sports_esports_outlined),
            title: Text(name),
            onTap: () => Navigator.of(ctx).pop(name),
          ),
      ])),
    );
    if (picked == null || !mounted) return;
    HangoutState.instance.minimize();
    HangoutState.instance.navigationKey.currentState
        ?.push(MaterialPageRoute(builder: (_) => choices[picked]!));
  }

  // --------------------------------------------------------------- view

  String get _duration {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _status {
    if (_ended != null) return _ended!;
    if (_error != null) return _error!;
    if (_connecting) return 'Connecting…';
    if (_reconnecting) return 'Reconnecting…';
    if (_ringing) return 'Ringing…';
    if (_peerWait != null) return 'Their connection dropped — waiting…';
    return _duration;
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final participants = <lk.Participant>[
      if (_room?.localParticipant != null) _room!.localParticipant!,
      ...?_room?.remoteParticipants.values,
    ];
    final warn = _error != null || _ended != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) HangoutState.instance.minimize();
      },
      child: Scaffold(
        backgroundColor: const Color(0xff130C0D),
        body: SafeArea(
          child: Column(children: [
            Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Return to hangout in background',
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: HangoutState.instance.minimize,
                )),
            if (_isHost)
              Wrap(alignment: WrapAlignment.center, children: [
                TextButton.icon(
                    onPressed: _hangoutSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Settings')),
                TextButton(
                    onPressed: _delegateHost,
                    child: const Text('Transfer host')),
                TextButton(
                    onPressed: _endForEveryone,
                    child: const Text('End call for everyone')),
              ]),
            if (_isHost &&
                (HangoutState.instance.session?['joinRequests'] as List? ??
                        const [])
                    .isNotEmpty)
              TextButton.icon(
                  onPressed: _showJoinRequests,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: Text(
                      'Join requests (${(HangoutState.instance.session?['joinRequests'] as List).length})')),
            Text(widget.title,
                style: Theme.of(context)
                    .textTheme
                    .displayLarge
                    ?.copyWith(fontSize: 26)),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (_reconnecting && _ended == null) ...[
                SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: n.gold)),
                const SizedBox(width: 8),
              ],
              Text(
                _status,
                key: const ValueKey('call-status'),
                style: TextStyle(
                    color: warn ? n.danger : (_reconnecting ? n.gold : n.mute),
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
            ]),
            if (_e2ee && _error == null) ...[
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.lock_rounded, size: 12, color: n.jade),
                const SizedBox(width: 4),
                Text('End-to-end encrypted',
                    style: TextStyle(
                        color: n.jade,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ]),
            ],
            TextButton.icon(
              onPressed: _connecting || _ended != null ? null : _playTogether,
              icon: const Icon(Icons.sports_esports_outlined),
              label: const Text('PLAY TOGETHER'),
            ),
            Expanded(
              child: _connecting
                  ? const Center(child: CircularProgressIndicator())
                  : GridView.builder(
                      padding: const EdgeInsets.all(24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 18,
                        crossAxisSpacing: 18,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: participants.length,
                      itemBuilder: (context, i) =>
                          _participantTile(n, participants[i]),
                    ),
            ),
            if (_manageable && !_connecting && _error == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                    _isHost
                        ? 'Tap someone to mute or remove them'
                        : 'Tap someone to mute them for you',
                    style: TextStyle(color: n.mute, fontSize: 11)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _roundButton(
                  key: const ValueKey('call-mic'),
                  icon: !_canSpeak
                      ? Icons.front_hand_rounded
                      : (_muted ? Icons.mic_off_rounded : Icons.mic_rounded),
                  active: _canSpeak && !_muted,
                  onTap: _connecting ? null : _toggleMute,
                ),
                if (_manageable) ...[
                  const SizedBox(width: 24),
                  _roundButton(
                    key: const ValueKey('call-add-person'),
                    icon: Icons.person_add_alt_1_rounded,
                    active: false,
                    onTap: _connecting || _ended != null ? null : _addPerson,
                  ),
                ],
                const SizedBox(width: 24),
                _roundButton(
                    icon: Icons.call_end_rounded,
                    active: false,
                    danger: true,
                    onTap: _leave),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _participantTile(NeonColors n, lk.Participant p) {
    final speaking = p.isSpeaking;
    final muted = p.isMuted;
    final remote = p is lk.RemoteParticipant;
    final name = p.name.isNotEmpty ? p.name : p.identity;
    return GestureDetector(
      onTap: remote ? () => _participantMenu(p) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: const Color(0xff241517),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: speaking ? n.jade : const Color(0xff3A2429),
              width: speaking ? 2.4 : 1),
          boxShadow: speaking
              ? [
                  BoxShadow(
                      color: n.jade.withValues(alpha: 0.4),
                      blurRadius: 18,
                      spreadRadius: -2)
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Avatar(name,
              size: 64, imageUrl: HangoutState.instance.avatars[p.identity]),
          const SizedBox(height: 10),
          Text(
              '${remote ? name : 'You'}${HangoutState.instance.ownerId == p.identity ? ' · Host' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                speaking
                    ? Icons.graphic_eq_rounded
                    : muted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                size: 14,
                color: muted ? n.mute : n.jade),
            if (remote && _manageable) ...[
              const SizedBox(width: 6),
              Icon(Icons.more_horiz_rounded, size: 16, color: n.mute),
            ],
          ]),
        ]),
      ),
    );
  }

  Widget _roundButton(
      {Key? key,
      required IconData icon,
      required bool active,
      VoidCallback? onTap,
      bool danger = false}) {
    final n = context.neon;
    final bg = danger ? n.danger : (active ? n.jade : const Color(0xff2C1A1D));
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(32),
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
        child: Icon(icon,
            color: danger || active ? Colors.white : n.mute, size: 26),
      ),
    );
  }
}
