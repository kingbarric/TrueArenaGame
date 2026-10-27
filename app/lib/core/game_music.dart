import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Background music for a game in progress.
/// Huudpoly uses a separately licensed cinematic track at a quieter volume.
/// Traitors has its own dark, slow cinematic music (Kevin MacLeod, CC BY 4.0)
/// that follows the game: hushed at night, calm but uneasy at the table,
/// tense while the votes go in, and heavy for a reveal — see [traitorsScene].
///
/// The bank is 22 public-domain solo piano recordings in `assets/music/`
/// (see `assets/music/CREDITS.md` for every source and licence). Each
/// session shuffles them and plays them back to back, so the music a game
/// opens with is different from the last one and a long game never loops
/// the same minute at you.
///
/// The two moods are deliberate: the board games get Satie, Debussy and
/// Chopin, which you can think over, while the party games get ragtime and
/// 1900s piano rolls, which carry a room. A session leads with its own
/// mood and keeps a couple from the other as a change of scene.
///
/// Every failure path here is silent. Music is decoration; a device that
/// won't play it must still play the game.
class GameMusic {
  GameMusic._();

  static const _enabledKey = 'ta_music_enabled';

  /// Quiet enough to sit under table talk and the agent's voice.
  static const _volume = 0.22;

  /// The result stinger sits a little forward of the background music — it's
  /// the moment, not the backdrop.
  static const _outcomeVolume = 0.42;

  /// How many tracks one session lines up before repeating.
  static const _playlistLength = 12;

  static const _calm = <String>[
    'gnossienne-1',
    'gnossienne-2',
    'gnossienne-3',
    'gnossienne-4',
    'gnossienne-5',
    'gymnopedie-1',
    'gymnopedie-3',
    'clair-de-lune-1905',
    'chopin-waltz-a-minor',
    'grieg-butterfly-1906',
  ];

  static const _cinematic = <String>['drums-of-the-deep'];

  /// Traitors, scene by scene. No piano: these are strings, choir, brass
  /// and dark synths, all slow enough to talk over.
  static const _traitors = <MusicMood, List<String>>{
    MusicMood.traitorsNight: ['traitors-ossuary-a-beginning', 'traitors-gathering-darkness'],
    MusicMood.traitorsTable: ['traitors-heart-of-nowhere', 'traitors-dark-times'],
    MusicMood.traitorsVote: ['traitors-crypto', 'traitors-controlled-chaos'],
    MusicMood.traitorsReveal: ['traitors-end-of-the-era', 'traitors-lightless-dawn'],
  };

  static const _lively = <String>[
    'harlem-rag',
    'pine-apple-rag',
    'the-favorite',
    'wall-street-rag',
    'palm-leaf-rag',
    'lightning-rag',
    'calla-lily-rag',
    'clothilda',
    'hot-hands',
    'blue-grass-rag',
    'canadian-capers',
    'topsy-turvy',
  ];

  static final AudioPlayer _player = AudioPlayer();

  static bool _enabled = true;
  static bool get enabled => _enabled;

  static List<String> _playlist = const [];
  static MusicMood? _mood;
  static int _position = 0;
  static double _sessionVolume = _volume;
  static StreamSubscription<PlayerState>? _stateSub;
  static int _sessionToken = 0;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;
  }

  /// Turning it off stops whatever is playing right now; turning it back on
  /// mid-game picks the session up again rather than waiting for the next.
  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    if (!value) {
      await stop();
    } else if (_playlist.isNotEmpty) {
      // stop() cancelled the advance listener on the way out, so turning the
      // music back on has to re-arm it — otherwise the session would play
      // one more track and then fall silent for the rest of the game.
      final token = ++_sessionToken;
      _armAdvance(token);
      unawaited(_playCurrent(token));
    }
  }

  /// Starts a session's music. [seed] makes the shuffle reproducible in
  /// tests; in the app it comes from the clock, which is what makes each
  /// session's running order different.
  static Future<void> start(MusicMood mood,
      {int? seed, bool autoplay = false}) async {
    await stop();
    if (autoplay) _enabled = true;
    _mood = mood;
    _sessionVolume = volumeFor(mood);
    _playlist =
        _shuffleFor(mood, seed ?? DateTime.now().microsecondsSinceEpoch);
    _position = 0;
    if (!_enabled) return;

    final token = ++_sessionToken;
    _armAdvance(token);
    await _playCurrent(token);
  }

  /// Moves the playlist on when a track ends. Cancelled by [stop], so every
  /// path that resumes playback must arm it again.
  static void _armAdvance(int token) {
    _stateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        unawaited(_advance(token));
      }
    });
  }

  /// Moves a session on to another scene's music — Traitors' night, table,
  /// vote and reveal — fading the current track out first rather than
  /// cutting it. Asking for the scene already playing changes nothing.
  static Future<void> switchTo(MusicMood mood) async {
    if (mood == _mood && _playlist.isNotEmpty) return;
    final token = _sessionToken;
    if (_enabled && _player.playing) {
      for (var step = 7; step >= 0; step--) {
        // Another switch (or a stop) took over: let it.
        if (token != _sessionToken) return;
        try {
          await _player.setVolume(_sessionVolume * step / 8);
        } catch (_) {/* no audio device: nothing to fade */}
        await Future<void>.delayed(const Duration(milliseconds: 140));
      }
    }
    if (token != _sessionToken) return;
    await start(mood);
  }

  /// How loud a session plays. The Traitors round table is barely there —
  /// people are talking, and should hear themselves over it; Huudpoly's
  /// cinematic track sits low too. Everything else plays at [_volume].
  static double volumeFor(MusicMood mood) => switch (mood) {
        MusicMood.traitorsTable => 0.07,
        MusicMood.cinematic => 0.14,
        _ => _volume,
      };

  /// Which Traitors scene a phase belongs to.
  static MusicMood traitorsScene(String phase) => switch (phase) {
        'Night' => MusicMood.traitorsNight,
        'Vote' || 'Revote' || 'SuddenDeath' || 'HostAssignVotes' || 'VoteReview' || 'Defense' || 'HostDecision' =>
          MusicMood.traitorsVote,
        'MorningReveal' || 'Elimination' => MusicMood.traitorsReveal,
        _ => MusicMood.traitorsTable,
      };

  static Future<void> stop() async {
    _sessionToken++;
    await _stateSub?.cancel();
    _stateSub = null;
    try {
      await _player.stop();
    } catch (_) {/* already stopped */}
  }

  /// This session's running order: the mood's own tracks first, shuffled,
  /// then a couple from the other mood so a long game gets a change of
  /// scene without wandering off tone.
  static List<String> _shuffleFor(MusicMood mood, int seed) {
    if (mood == MusicMood.cinematic) return List.of(_cinematic);
    final scene = _traitors[mood];
    // A plain LCG — the order only has to look arbitrary, and this keeps it
    // reproducible from [seed] without pulling in dart:math's generator.
    var state = seed & 0x7FFFFFFF;
    int next(int max) {
      state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
      return state % max;
    }

    List<String> shuffled(List<String> source) {
      final list = List<String>.of(source);
      for (var i = list.length - 1; i > 0; i--) {
        final j = next(i + 1);
        final tmp = list[i];
        list[i] = list[j];
        list[j] = tmp;
      }
      return list;
    }

    // A Traitors scene keeps to its own tracks — no piano wandering in.
    if (scene != null) return shuffled(scene);
    final primary = shuffled(mood == MusicMood.calm ? _calm : _lively);
    final secondary = shuffled(mood == MusicMood.calm ? _lively : _calm);
    return [...primary, ...secondary.take(2)].take(_playlistLength).toList();
  }

  static Future<void> _advance(int token) async {
    if (token != _sessionToken) return;
    _position = (_position + 1) % _playlist.length;
    await _playCurrent(token);
  }

  static Future<void> _playCurrent(int token) async {
    if (!_enabled || _playlist.isEmpty || token != _sessionToken) return;
    try {
      await _player.setAsset('assets/music/${_playlist[_position]}.m4a');
      if (token != _sessionToken) return;
      await _player.setVolume(_sessionVolume);
      await _player.play();
    } catch (_) {
      // Couldn't load or play this one — the session goes quiet rather than
      // spinning through the rest of the playlist failing on each.
    }
  }

  /// A short piece at the final whistle, matched to the result: a bright
  /// 1921 rag for a win, Satie's downcast opening phrase for a loss.
  ///
  /// It replaces the session's playlist rather than layering over it — two
  /// pieces of piano at once is a mess — and it honours the same off switch
  /// as everything else, because someone who turned the music off meant it.
  static Future<void> playOutcome({required bool won}) async {
    await stop(); // ends the playlist and its advance listener
    _mood = null;
    if (!_enabled) return;
    try {
      await _player.setAsset('assets/music/${won ? 'victory' : 'defeat'}.m4a');
      await _player.setVolume(_outcomeVolume);
      await _player.play();
    } catch (_) {
      // No stinger is a fine outcome; the results screen stands on its own.
    }
  }

  /// Exposed for tests and for the settings screen's description.
  static int get trackCount =>
      _calm.length + _lively.length + _cinematic.length + _traitors.values.fold(0, (sum, l) => sum + l.length);

  /// The running order [start] would use, without touching the audio device
  /// — the part of this worth testing.
  @visibleForTesting
  static List<String> debugPlaylist(MusicMood mood, {required int seed}) =>
      _shuffleFor(mood, seed);

  @visibleForTesting
  static MusicMood debugMoodOf(String slug) => _cinematic.contains(slug)
      ? MusicMood.cinematic
      : _calm.contains(slug)
          ? MusicMood.calm
          : _traitors.entries.where((e) => e.value.contains(slug)).map((e) => e.key).firstOrNull ??
              MusicMood.lively;

  /// The mood a game should ask for. Kept here rather than on each screen so
  /// adding a game is one line in one place.
  static MusicMood moodFor(String gameType) => switch (gameType) {
        'monopoly' => MusicMood.cinematic,
        'truearena' => MusicMood.traitorsTable,
        'draughts' || 'chess' || 'goosi' || 'ludo' => MusicMood.calm,
        _ => MusicMood.lively,
      };
}

/// Which half of the bank a game draws from.
enum MusicMood {
  /// Satie, Debussy, Chopin — for a board game you sit and think over.
  calm,

  /// Ragtime and 1900s piano rolls — for the loud, chatty party games.
  lively,

  /// Quiet cinematic percussion for Huudpoly.
  cinematic,

  /// Traitors at night: hushed, eerie synths.
  traitorsNight,

  /// Traitors at the table: calm but uneasy strings and choir.
  traitorsTable,

  /// Traitors while the votes go in: tense.
  traitorsVote,

  /// Traitors' reveals: heavy brass, bells and timpani.
  traitorsReveal,
}
