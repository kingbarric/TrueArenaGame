import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/core/game_music.dart';

/// Pins the playlist rules. Playback itself needs a real audio device, so
/// what's testable — and what actually matters to a player — is that the
/// running order is a sensible, varied, on-tone one.
void main() {
  test('a game gets the mood its pace calls for', () {
    expect(GameMusic.moodFor('draughts'), MusicMood.calm);
    expect(GameMusic.moodFor('goosi'), MusicMood.calm);
    expect(GameMusic.moodFor('wordbluff'), MusicMood.lively);
    expect(GameMusic.moodFor('truearena'), MusicMood.lively);
  });

  test('the bank is the 22 tracks that ship in assets/music', () {
    expect(GameMusic.trackCount, 22);
  });

  group('session playlists', () {
    test('lead with the requested mood and never repeat a track', () {
      for (final mood in MusicMood.values) {
        final list = GameMusic.debugPlaylist(mood, seed: 4242);
        expect(list, hasLength(12));
        expect(list.toSet(), hasLength(12), reason: 'no track appears twice');
        // The first several must be from the mood's own half — a board game
        // shouldn't open on ragtime.
        expect(GameMusic.debugMoodOf(list.first), mood);
        expect(GameMusic.debugMoodOf(list[5]), mood);
      }
    });

    test('carry a couple from the other half as a change of scene', () {
      final list = GameMusic.debugPlaylist(MusicMood.calm, seed: 7);
      final other = list.where((t) => GameMusic.debugMoodOf(t) == MusicMood.lively);
      expect(other, hasLength(2));
    });

    test('two sessions get different running orders', () {
      final a = GameMusic.debugPlaylist(MusicMood.lively, seed: 1);
      final b = GameMusic.debugPlaylist(MusicMood.lively, seed: 2);
      expect(a, isNot(equals(b)));
    });

    test('the same seed always gives the same order', () {
      expect(
        GameMusic.debugPlaylist(MusicMood.calm, seed: 99),
        GameMusic.debugPlaylist(MusicMood.calm, seed: 99),
      );
    });
  });
}
