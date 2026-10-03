import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The small sounds a game makes: picking a piece up, putting it down, a
/// capture, a refused tap.
///
/// They're synthesised rather than sampled — the whole set is under 100 KB
/// of short WAVs, which is less than one recorded sound effect would cost,
/// and each is tuned to the moment it marks. WAV rather than a compressed
/// format on purpose: these have to land the instant a finger touches the
/// board, and there's no decode step to wait through.
///
/// Every sound gets its own player, loaded once and rewound to replay, so
/// tapping quickly never waits on a file being opened.
class GameSfx {
  GameSfx._();

  static const _enabledKey = 'ta_sfx_enabled';

  /// Under the music, over nothing — these are punctuation, not the score,
  /// and quiet enough to sit through a twenty-five seed sowing without
  /// wearing on you.
  static const _volume = 0.38;

  static const _names = <String>[
    'select', 'move', 'illegal', 'capture', 'captured', 'king',
    'chain1', 'chain2', 'chain3', 'chain4',
    'seed1', 'seed2', 'seed3', 'seed4', 'scoop', 'settle',
    'crank', 'wheel_stop', 'card_play', 'card_draw',
    'dice_roll',
  ];

  static final Map<String, AudioPlayer> _players = {};
  static bool _enabled = true;
  static bool _warmed = false;

  static bool get enabled => _enabled;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  /// Opens every sound ahead of the first tap. Called when a game screen
  /// starts; safe to call again, and silent if a sound won't load.
  static Future<void> warmUp() async {
    if (_warmed) return;
    _warmed = true;
    for (final name in _names) {
      try {
        final player = AudioPlayer();
        await player.setAsset('assets/sfx/$name.wav');
        await player.setVolume(_volume);
        _players[name] = player;
      } catch (_) {
        // A sound that won't load simply never plays.
      }
    }
  }

  /// Picking a piece up.
  static void select() => _play('select');

  /// Putting one down.
  static void move() => _play('move');

  /// A tap the board won't accept.
  static void illegal() => _play('illegal');

  /// You took a piece.
  static void capture() => _play('capture');

  /// One of yours was taken.
  static void captured() => _play('captured');

  /// A man was crowned.
  static void king() => _play('king');

  /// One more jump added to a capture sequence. The pitch climbs with
  /// [step], so a double or triple take is audible as it's built.
  static void chain(int step) => _play('chain${step.clamp(1, 4)}');

  /// A seed landing in a pit. [index] cycles the pitch so a long sowing
  /// never sounds like a machine ticking.
  static void seed(int index) => _play('seed${index % 4 + 1}');

  /// The hand gathering a pit up to carry on sowing.
  static void scoop() => _play('scoop');

  /// The last seed of a turn, landing in a pit that was empty — the full
  /// stop at the end of a sowing.
  static void settle() => _play('settle');

  /// One click of the category wheel's ratchet, played per slice it passes.
  static void crank() => _play('crank');

  /// The wheel settling into the slice it stopped on.
  static void wheelStop() => _play('wheel_stop');

  /// A cup shaking and releasing the dice.
  static void diceRoll() => _play('dice_roll');

  /// A card laid onto the discard pile — a quick, soft flick, not a thud.
  static void cardPlay() => _play('card_play');

  /// Going to the market — a softer, slower paper-slide than [cardPlay],
  /// so the two stay easy to tell apart by ear alone.
  static void cardDraw() => _play('card_draw');

  static void _play(String name) {
    if (!_enabled) return;
    final player = _players[name];
    if (player == null) return;
    // Rewind first so a repeated tap retriggers instead of being ignored,
    // and never await play() — it completes when the sound *finishes*.
    unawaited(player.seek(Duration.zero).then((_) => player.play()).catchError((_) {}));
  }
}
