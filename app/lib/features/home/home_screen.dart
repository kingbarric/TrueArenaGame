import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/coin_tier_badge.dart';
import '../../widgets/game_badge.dart';
import '../../widgets/idle_wiggle.dart';
import '../../widgets/motif.dart';
import '../../widgets/neon.dart';
import '../../widgets/playhuud_logo.dart';
import '../chess/chess_lobby_screen.dart';
import '../draughts/draughts_mode_screen.dart';
import '../games/game_select_screen.dart';
import '../goosi/goosi_lobby_screen.dart';
import '../huud/huud_models.dart' show huudGameNames;
import '../huudspace/create_huud_sheet.dart';
import '../modes/mode_select_screen.dart';
import '../onboarding/guest_gate.dart';
import '../profile/profile_screen.dart';
import '../wordbluff/wordbluff_lobby_screen.dart';
import '../whot/whot_lobby_screen.dart';
import '../ludo/ludo_lobby_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final app = AppScope.of(context);
    // Your own card shows your username; full names are for your friends'
    // lists, not your own header.
    final name = app.user?.username ?? app.user?.displayName ?? 'Player';
    final isGuest = app.identity == Identity.guest;

    return Scaffold(
      body: Stack(
        children: [
          // Same three-spot layout as the welcome screen (dice/cup in the top
          // corners, drum in the empty middle band by height-fraction so it
          // never creeps under the headline or the New Game button) — mirrored
          // left/right so the two screens don't look identical.
          Positioned(
              left: -30,
              top: 90,
              child: DiceMotif(color: n.ink, size: 120, rotation: -0.22)),
          Positioned(
              right: -15,
              top: 90,
              child: PalmWineCupMotif(color: n.ink, size: 110, rotation: 0.08)),
          Positioned(
            right: -50,
            top: MediaQuery.sizeOf(context).height * 0.40,
            child: DrumMotif(color: n.ink, size: 220, rotation: 0.05),
          ),
          // The nav pill itself lives in `MainShell` now, above every tab —
          // Home just leaves room for it at the bottom.
          _content(context, n, app, name, isGuest),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, NeonColors n, AppState app, String name,
      bool isGuest) {
    return SafeArea(
        child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MarqueeBar(
              'Friday Crew  •  season 1  •  game 12 of 100  •  your move'),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
            child: Bouncy(
              feel: BouncyFeel.soft,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen())),
              child: Row(
                children: [
                  Avatar(name,
                      size: 40,
                      emoji: app.avatarEmoji,
                      imagePath: app.avatarImagePath,
                      imageUrl: app.user?.avatarUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(name,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                            ),
                            const SizedBox(width: 8),
                            _TierBadgeLoader(app: app),
                          ],
                        ),
                        if (isGuest)
                          Text('Guest — this device only',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: n.mute)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: n.mute, size: 20),
                ],
              ),
            ),
          ),
          // Only games here: joining or reopening a Huud lives on the Huud tab.
          const SizedBox(height: 24),
          // The badge row *is* the picker — there used to be a "New game"
          // button here too, which opened a screen listing these same four
          // games and pushed these same lobbies. Two doors to one room. The
          // headline now sits directly above the row it's describing, and the
          // row is the primary action. (`GameSelectScreen` still exists: it's
          // the picker for screens that aren't Home, e.g. Chats and Friends.)
          // The logo gets a line to itself, right above the games.
          const Center(
            key: ValueKey('home-logo'),
            child: PlayHuudLogo(width: 190, height: 64),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
            child: Text('Tap a game to play',
                key: const ValueKey('home-tap-to-play'),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: n.ink, fontWeight: FontWeight.w800)),
          ),
          // Two to a row, so each game's artwork is big enough to read.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: LayoutBuilder(builder: (context, constraints) {
              const columns = 2;
              final tileWidth =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                for (final game in gameCatalog)
                  SizedBox(
                      width: tileWidth, child: _gameTile(context, n, game)),
              ]);
            }),
          ),
          if (isGuest) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: NeonCard(
                accent: n.jade,
                child: Row(children: [
                  Icon(Icons.workspace_premium_outlined,
                      color: n.jade, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        'Add an account to keep your stats after this game.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: n.mid)),
                  ),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 96),
        ],
      ),
    ));
  }

  Widget _gameTile(BuildContext context, NeonColors n, GameCatalogEntry g) {
    final artwork = GameBadge.artworkFor(g.id);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Opacity(
            opacity: g.available ? 1 : 0.45,
            // Each game gives a little shake now and then, at its own
            // random moment, so the shelf feels alive.
            child: IdleWiggle(
              child: artwork == null
                  ? GameBadge(gameId: g.id)
                  : Image.asset(artwork, fit: BoxFit.contain),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          g.name,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: g.available ? n.ink : n.mute,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
        ),
      ],
    );
    final cabinet = context.neonDesign.kind == NeonDesignKind.cabinet;
    return Bouncy(
      key: ValueKey('home-game-${g.id}'),
      feel: BouncyFeel.wobble,
      onTap: () => _openGame(context, g),
      child: cabinet
          ? Container(
              padding: const EdgeInsets.fromLTRB(4, 7, 4, 8),
              decoration: BoxDecoration(
                color: n.panel,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: kCabinetInk, width: 2.5),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black38,
                      blurRadius: 0,
                      offset: Offset(3, 4))
                ],
              ),
              child: content,
            )
          : NeonCard(
              glass: false,
              padding: const EdgeInsets.fromLTRB(4, 7, 4, 8),
              child: content,
            ),
    );
  }

  /// Same tap behavior as `GameSelectScreen`'s tiles — duplicated rather than
  /// shared because it's four lines and pulling it into a third place would
  /// cost more than it saves.
  Future<void> _openGame(BuildContext context, GameCatalogEntry g) async {
    if (!g.available) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${g.name} is coming soon')));
      return;
    }
    // Games are played in a Huud. Only an account can host one, so guests
    // (and anyone signed out) keep the quick lobby: bots, a friend's code.
    final app = AppScope.of(context);
    if (app.identity == Identity.account && huudGameNames.containsKey(_huudType(g.id))) {
      await openHuudForGame(context, _huudType(g.id), quickPlay: () => _openQuickLobby(context, g));
      return;
    }
    await _openQuickLobby(context, g);
  }

  static String _huudType(String catalogId) => catalogId == 'bluff' ? 'wordbluff' : catalogId;

  /// The game's own lobby: play a bot, open a quick table, join by code.
  Future<void> _openQuickLobby(BuildContext context, GameCatalogEntry g) async {
    if (g.id == 'draughts') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const DraughtsModeScreen(),
      ));
    } else if (g.id == 'bluff' ||
        g.id == 'chess' ||
        g.id == 'whot' ||
        g.id == 'ludo' ||
        g.id == 'goosi') {
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
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const ModeSelectScreen()));
    }
  }
}

/// Fetches the tier once per screen build and fades the badge in once it
/// resolves — silently shows nothing on failure (a guest's very first
/// request, a flaky connection) rather than an error chip next to someone's
/// name.
class _TierBadgeLoader extends StatefulWidget {
  const _TierBadgeLoader({required this.app});
  final AppState app;

  @override
  State<_TierBadgeLoader> createState() => _TierBadgeLoaderState();
}

class _TierBadgeLoaderState extends State<_TierBadgeLoader> {
  late final Future<CoinTierInfo> _future = widget.app.fetchTier();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CoinTierInfo>(
      future: _future,
      builder: (context, snap) {
        final info = snap.data;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
                scale: anim, alignment: Alignment.centerLeft, child: child),
          ),
          child: info == null
              ? const SizedBox(key: ValueKey('empty'), width: 0, height: 0)
              : CoinTierBadge(key: ValueKey(info.tier), info: info),
        );
      },
    );
  }
}
