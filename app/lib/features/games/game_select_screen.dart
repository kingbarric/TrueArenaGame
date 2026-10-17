import '../../core/app_state.dart';
import '../huudspace/create_huud_sheet.dart';
import 'package:flutter/material.dart';

import '../../theme/neon_theme.dart';
import '../../widgets/game_badge.dart';
import '../../widgets/neon.dart';
import '../chess/chess_lobby_screen.dart';
import '../slayhuud/slay_hub_screen.dart';
import '../draughts/draughts_mode_screen.dart';
import '../goosi/goosi_lobby_screen.dart';
import '../whot/whot_lobby_screen.dart';
import '../ludo/ludo_lobby_screen.dart';
import '../modes/mode_select_screen.dart';
import '../onboarding/guest_gate.dart';
import '../wordbluff/wordbluff_lobby_screen.dart';

/// One entry in the games grid. Traitors, Word Bluff, and Draughts are all
/// playable today; the catalog (and the `available` flag) exists so a
/// future game is a new entry here, not a new screen — flip it to `true`
/// once it's real.
class GameCatalogEntry {
  const GameCatalogEntry({
    required this.id,
    required this.name,
    required this.emoji,
    required this.tagline,
    this.available = false,
  });

  final String id;
  final String name;
  final String emoji;
  final String tagline;
  final bool available;
}

// Two per row on the games grid: Traitors · SlayHuud, Word Bluff · Monopoly,
// Chess · Draughts, Ludo · Whot, then Macala.
const List<GameCatalogEntry> gameCatalog = [
  GameCatalogEntry(
    id: 'truearena',
    name: 'Traitors',
    emoji: '🎭',
    tagline: 'Social deduction · 5 modes',
    available: true,
  ),
  GameCatalogEntry(
    id: 'slayhuud',
    name: 'SlayHuud',
    emoji: '✨',
    tagline: 'Style · compete · own the spotlight',
    available: true,
  ),
  GameCatalogEntry(
    id: 'bluff',
    name: 'Word Bluff',
    emoji: '🗣️',
    tagline: 'Spin & describe · 2 teams',
    available: true,
  ),
  GameCatalogEntry(
    id: 'monopoly',
    name: 'Monopoly',
    emoji: '🏠',
    tagline: '2–8 players · buy, build & trade',
    available: true,
  ),
  GameCatalogEntry(
    id: 'chess',
    name: 'Chess',
    emoji: '♞',
    tagline: '1v1 · standard rules · timed',
    available: true,
  ),
  GameCatalogEntry(
    id: 'draughts',
    name: 'Draughts',
    emoji: '⚫',
    tagline: '1v1 · 10x10 · flying kings',
    available: true,
  ),
  GameCatalogEntry(
    id: 'ludo',
    name: 'Ludo',
    emoji: '🎲',
    tagline: '2–4 players · two dice · Cyber Agents',
    available: true,
  ),
  GameCatalogEntry(
    id: 'whot',
    name: 'Whot',
    emoji: '🔴',
    tagline: '2–20 players · shapes & numbers · shed your hand',
    available: true,
  ),
  GameCatalogEntry(
    id: 'goosi',
    name: 'Macala',
    emoji: '🫘',
    tagline: '2 players · 12 houses · capture & sow',
    available: true,
  ),
];

/// The grid shown from Home's "New game" — pick a game first, then (for
/// TrueArena today) a mode.
class GameSelectScreen extends StatelessWidget {
  const GameSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a game')),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.92,
          ),
          itemCount: gameCatalog.length,
          itemBuilder: (context, i) {
            final g = gameCatalog[i];
            return NeonCard(
              mirror: i.isOdd,
              selected: g.available,
              accent: g.available ? n.brand : null,
              onTap: () async {
                if (!g.available) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${g.name} is coming soon')));
                  return;
                }
                if (g.id == 'slayhuud') {
                  void solo() => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SlayHubScreen()));
                  // Accounts play it in a Huud ("quick game" is SlayHuud
                  // solo); guests get the hub, as on Home.
                  if (AppScope.of(context).identity == Identity.account) {
                    await openHuudForGame(context, 'slayhuud', quickPlay: solo);
                  } else {
                    solo();
                  }
                  return;
                }
                if (g.id == 'monopoly') {
                  await openHuudForGame(context, 'monopoly');
                  return;
                }
                if (g.id == 'draughts') {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const DraughtsModeScreen(),
                  ));
                } else if (g.id == 'bluff' ||
                    g.id == 'chess' ||
                    g.id == 'whot' ||
                    g.id == 'ludo' ||
                    g.id == 'goosi') {
                  // These lobbies create the room the moment they open, so
                  // the guest check has to happen right here, before pushing it.
                  if (!await canHostOrPromptToVerify(context)) return;
                  if (!context.mounted) return;
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => switch (g.id) {
                      'bluff' => const WordBluffLobbyScreen(),
                      'whot' => const WhotLobbyScreen(),
                      'goosi' => const GoosiLobbyScreen(),
                      'chess' => const ChessLobbyScreen(),
                      _ => const LudoLobbyScreen(),
                    },
                  ));
                } else {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ModeSelectScreen()));
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GameBadge(gameId: g.id, size: 64, dimmed: !g.available),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: g.available ? n.ink : n.mute)),
                      const SizedBox(height: 4),
                      Text(g.tagline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: g.available ? n.mid : n.mute)),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
