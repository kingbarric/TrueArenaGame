import 'package:flutter/material.dart';

import 'huud_signal_art.dart';

/// Emoji strings remain wire/storage identifiers; these widgets render Huud art.
class HuudArtSpec {
  const HuudArtSpec(this.asset, this.label);
  final String asset;
  final String label;
}

class HuudArt {
  HuudArt._();
  static String normalize(String token) => token.replaceAll('\uFE0F', '');
  static const _tokens = <String, HuudArtSpec>{
    '😴': HuudArtSpec('assets/images/huud_ui/sleep.png', 'Resting Huud'),
    '🌙': HuudArtSpec('assets/images/huud_ui/sleep.png', 'Resting Huud'),
    '🔑': HuudArtSpec('assets/images/huud_ui/key.png', 'Join code'),
    '🗝': HuudArtSpec('assets/images/huud_ui/key.png', 'Join code'),
    '🏆': HuudArtSpec('assets/images/huud_ui/trophy.png', 'Trophy'),
    '🏅': HuudArtSpec('assets/images/huud_ui/trophy.png', 'Trophy'),
    '🥇': HuudArtSpec('assets/images/huud_ui/trophy.png', 'Trophy'),
    '🥈': HuudArtSpec('assets/images/huud_ui/trophy.png', 'Trophy'),
    '🥉': HuudArtSpec('assets/images/huud_ui/trophy.png', 'Trophy'),
    '✋': HuudArtSpec('assets/images/huud_ui/hand.png', 'Raised hand'),
    '👋': HuudArtSpec('assets/images/huud_ui/hand.png', 'Raised hand'),
    '👆': HuudArtSpec('assets/images/huud_ui/hand.png', 'Raised hand'),
    '👏': HuudArtSpec('assets/images/huud_ui/hand.png', 'Raised hand'),
    '🤖': HuudArtSpec('assets/images/huud_ui/robot.png', 'Cyber Agent'),
    '💻': HuudArtSpec('assets/images/huud_ui/robot.png', 'Cyber Agent'),
    '🔬': HuudArtSpec('assets/images/huud_ui/robot.png', 'Cyber Agent'),
    '❤': HuudArtSpec('assets/images/huud_ui/heart.png', 'Heart'),
    '💛': HuudArtSpec('assets/images/huud_ui/heart.png', 'Heart'),
    '💚': HuudArtSpec('assets/images/huud_ui/heart.png', 'Heart'),
    '👑': HuudArtSpec('assets/images/huud_ui/crown.png', 'Host crown'),
    '🛡': HuudArtSpec('assets/images/huud_ui/shield.png', 'Safety check'),
    '✅': HuudArtSpec('assets/images/huud_ui/shield.png', 'Safety check'),
    '🔒': HuudArtSpec('assets/images/huud_ui/lock.png', 'Private'),
    '🔓': HuudArtSpec('assets/images/huud_ui/key.png', 'Unlocked'),
    '🔔': HuudArtSpec('assets/images/huud_ui/bell.png', 'Notifications'),
    '🔕': HuudArtSpec('assets/images/huud_ui/bell.png', 'Notifications'),
    '👀': HuudArtSpec('assets/images/huud_ui/eyes.png', 'Watching'),
    '👁': HuudArtSpec('assets/images/huud_ui/eyes.png', 'Watching'),
    '🙈': HuudArtSpec('assets/images/huud_ui/eyes.png', 'Watching'),
    '✨': HuudArtSpec('assets/images/huud_ui/sparkle.png', 'Sparkle'),
    '★': HuudArtSpec('assets/images/huud_ui/sparkle.png', 'Sparkle'),
    '🌟': HuudArtSpec('assets/images/huud_ui/sparkle.png', 'Sparkle'),
    '🌠': HuudArtSpec('huud-signal:shooting-star', 'Shooting star'),
    '🎉': HuudArtSpec('assets/images/huud_ui/party.png', 'Celebration'),
    '🔥': HuudArtSpec('assets/images/huud_ui/fire.png', 'Fire'),
    '⏳': HuudArtSpec('assets/images/huud_ui/clock.png', 'Time'),
    '⌚': HuudArtSpec('assets/images/huud_ui/clock.png', 'Time'),
    '🕗': HuudArtSpec('assets/images/huud_ui/clock.png', 'Time'),
    '📅': HuudArtSpec('assets/images/huud_ui/calendar.png', 'Date'),
    '🌍': HuudArtSpec('assets/images/huud_ui/globe.png', 'World'),
    '🗺': HuudArtSpec('assets/images/huud_ui/globe.png', 'World'),
    '✈': HuudArtSpec('assets/images/huud_ui/globe.png', 'World'),
    '🚪': HuudArtSpec('assets/images/huud_ui/door.png', 'Doorway'),
    '🔗': HuudArtSpec('assets/images/huud_ui/link.png', 'Share link'),
    '🗑': HuudArtSpec('assets/images/huud_ui/trash.png', 'Delete'),
    '🚫': HuudArtSpec('assets/images/huud_ui/stop.png', 'Stop'),
    '🙅': HuudArtSpec('assets/images/huud_ui/stop.png', 'Stop'),
    '❌': HuudArtSpec('assets/images/huud_ui/stop.png', 'Stop'),
    '⚠': HuudArtSpec('assets/images/huud_ui/stop.png', 'Stop'),
    '🤔': HuudArtSpec('assets/images/huud_ui/thinking.png', 'Thinking'),
    '❓': HuudArtSpec('assets/images/huud_ui/thinking.png', 'Thinking'),
    '🎁': HuudArtSpec('assets/images/huud_ui/gift.png', 'Gift'),
    '💌': HuudArtSpec('assets/images/huud_ui/gift.png', 'Gift'),
    '⚡': HuudArtSpec('assets/images/huud_ui/lightning.png', 'Quick game'),
    '👍': HuudArtSpec('assets/images/huud_ui/thumb.png', 'Like'),
    '😂': HuudArtSpec('assets/images/huud_ui/laugh.png', 'Laughing Huud'),
    '😮': HuudArtSpec('assets/images/huud_ui/wow.png', 'Surprised Huud'),
    '📰': HuudArtSpec('assets/images/huud_ui/book.png', 'Book'),
    '📜': HuudArtSpec('assets/images/huud_ui/book.png', 'Book'),
    '🎓': HuudArtSpec('assets/images/huud_ui/book.png', 'Book'),
    '🎵': HuudArtSpec('assets/images/huud_ui/music.png', 'Music'),
    '🍔': HuudArtSpec('assets/images/huud_ui/food.png', 'Food'),
    '⚽': HuudArtSpec('assets/images/huud_ui/sport.png', 'Sport'),
    '🌿': HuudArtSpec('assets/images/huud_ui/leaf.png', 'Nature'),
    '🌱': HuudArtSpec('assets/images/huud_ui/leaf.png', 'Nature'),
    '📡': HuudArtSpec('assets/images/nav/live_active.png', 'Live'),
    '🔴': HuudArtSpec('assets/images/nav/live_active.png', 'Live'),
    '🟢': HuudArtSpec('assets/images/nav/live_active.png', 'Live'),
    '📣': HuudArtSpec('assets/images/nav/live_active.png', 'Live'),
    '📢': HuudArtSpec('assets/images/nav/live_active.png', 'Live'),
    '🎙': HuudArtSpec('assets/images/nav/live_active.png', 'Live'),
    '📺': HuudArtSpec('assets/images/nav/live_active.png', 'Live'),
    '💬': HuudArtSpec('assets/images/nav/messages_active.png', 'Chat'),
    '🗣': HuudArtSpec('assets/images/nav/messages_active.png', 'Chat'),
    '👫': HuudArtSpec('assets/images/nav/friends_active.png', 'Friends'),
    '👥': HuudArtSpec('assets/images/nav/friends_active.png', 'Friends'),
    '🤝': HuudArtSpec('assets/images/nav/friends_active.png', 'Friends'),
    '👯': HuudArtSpec('assets/images/nav/friends_active.png', 'Friends'),
    '🏠': HuudArtSpec('assets/images/nav/huud_active.png', 'Huud'),
    '🛋': HuudArtSpec('assets/images/nav/huud_active.png', 'Huud'),
    '🪑': HuudArtSpec('assets/images/nav/huud_active.png', 'Huud'),
    '🎮': HuudArtSpec('assets/images/nav/games_active.png', 'Games'),
    '🎡': HuudArtSpec('assets/images/nav/games_active.png', 'Games'),
    '🏁': HuudArtSpec('assets/images/nav/games_active.png', 'Games'),
    '🎬': HuudArtSpec('assets/images/nav/foryou_active.png', 'Video'),
    '👷': HuudArtSpec('assets/images/nav/you_active.png', 'Player'),
    '🦸': HuudArtSpec('assets/images/nav/you_active.png', 'Player'),
    '🎲': HuudArtSpec('assets/images/game_icons/ludo.png', 'Ludo'),
    '⚫': HuudArtSpec('assets/images/game_icons/draft.png', 'Draughts'),
    '🫘': HuudArtSpec('assets/images/game_icons/goosi.png', 'Macala'),
    '🥜': HuudArtSpec('assets/images/game_icons/goosi.png', 'Macala'),
    '🃏': HuudArtSpec('assets/images/game_icons/whot.png', 'Whot'),
    '♟': HuudArtSpec('assets/images/game_icons/chess.png', 'Chess'),
    '♚': HuudArtSpec('assets/images/game_icons/chess.png', 'Chess'),
    '♛': HuudArtSpec('assets/images/game_icons/chess.png', 'Chess'),
    '♜': HuudArtSpec('assets/images/game_icons/chess.png', 'Chess'),
    '♝': HuudArtSpec('assets/images/game_icons/chess.png', 'Chess'),
    '♞': HuudArtSpec('assets/images/game_icons/chess.png', 'Chess'),
    '🤫': HuudArtSpec('assets/images/game_icons/word_bluff.png', 'Word Bluff'),
    '🦊': HuudArtSpec('assets/images/huud_ui/avatar_fox.png', 'Fox'),
    '🐾': HuudArtSpec('assets/images/huud_ui/avatar_fox.png', 'Fox'),
    '🐺': HuudArtSpec('assets/images/huud_ui/avatar_wolf.png', 'Wolf'),
    '🎭': HuudArtSpec('assets/images/huud_ui/avatar_mask.png', 'Mask'),
    '🕵':
        HuudArtSpec('assets/images/huud_ui/avatar_detective.png', 'Detective'),
    '🦁': HuudArtSpec('assets/images/huud_ui/avatar_lion.png', 'Lion'),
    '🐸': HuudArtSpec('assets/images/huud_ui/avatar_frog.png', 'Frog'),
    '🦄': HuudArtSpec('assets/images/huud_ui/avatar_unicorn.png', 'Unicorn'),
    '🐙': HuudArtSpec('assets/images/huud_ui/avatar_octopus.png', 'Octopus'),
    '🦉': HuudArtSpec('assets/images/huud_ui/avatar_owl.png', 'Owl'),
    '🐲': HuudArtSpec('assets/images/huud_ui/avatar_dragon.png', 'Dragon'),
    '👺': HuudArtSpec('assets/images/huud_ui/avatar_guardian.png', 'Guardian'),
    '👽': HuudArtSpec('assets/images/huud_ui/avatar_alien.png', 'Alien'),
    '🥷': HuudArtSpec('assets/images/huud_ui/avatar_ninja.png', 'Ninja'),
    '😈':
        HuudArtSpec('assets/images/huud_ui/avatar_trickster.png', 'Trickster'),
    '😇': HuudArtSpec('assets/images/huud_ui/avatar_angel.png', 'Angel'),
    '😠': HuudArtSpec('assets/images/huud_ui/avatar_trickster.png', 'Unhappy'),
    '👗': HuudArtSpec('assets/images/huud_ui/dress.png', 'Dress'),
    '👚': HuudArtSpec('assets/images/huud_ui/shirt.png', 'Top'),
    '👕': HuudArtSpec('assets/images/huud_ui/shirt.png', 'Shirt'),
    '👖': HuudArtSpec('assets/images/huud_ui/trousers.png', 'Trousers'),
    '🩱': HuudArtSpec('assets/images/huud_ui/skirt.png', 'Skirt'),
    '👠': HuudArtSpec('assets/images/huud_ui/shoe.png', 'Shoes'),
    '👜': HuudArtSpec('assets/images/huud_ui/bag.png', 'Bag'),
    '💍': HuudArtSpec('assets/images/huud_ui/ring.png', 'Jewellery'),
    '💄': HuudArtSpec('assets/images/huud_ui/makeup.png', 'Makeup'),
    '💇': HuudArtSpec('assets/images/huud_ui/hair.png', 'Hair'),
    '🪐': HuudArtSpec('huud-signal:planet', 'Planet'),
    '🌌': HuudArtSpec('huud-signal:galaxy', 'Galaxy'),
    '☄': HuudArtSpec('huud-signal:comet', 'Comet'),
    '🌑': HuudArtSpec('huud-signal:new-moon', 'New moon'),
    '🌒': HuudArtSpec('huud-signal:waxing-crescent', 'Waxing crescent'),
    '🌓': HuudArtSpec('huud-signal:first-quarter', 'First quarter'),
    '🌔': HuudArtSpec('huud-signal:waxing-gibbous', 'Waxing gibbous'),
    '🌕': HuudArtSpec('huud-signal:full-moon', 'Full moon'),
    '🌘': HuudArtSpec('huud-signal:waning-crescent', 'Waning crescent'),
    '🌚': HuudArtSpec('huud-signal:dark-face', 'Dark moon'),
    '🌝': HuudArtSpec('huud-signal:light-face', 'Bright moon'),
    '🔮': HuudArtSpec('huud-signal:crystal', 'Crystal'),
    '🧿': HuudArtSpec('huud-signal:talisman', 'Eye talisman'),
    '🕯': HuudArtSpec('huud-signal:candle', 'Candle'),
    '🪞': HuudArtSpec('huud-signal:mirror', 'Mirror'),
    '🪄': HuudArtSpec('huud-signal:wand', 'Wand'),
    '🕳': HuudArtSpec('huud-signal:portal', 'Portal'),
    '🛸': HuudArtSpec('huud-signal:ufo', 'Spacecraft'),
    '🗿': HuudArtSpec('huud-signal:stone', 'Stone face'),
    '🧬': HuudArtSpec('huud-signal:dna', 'DNA'),
    '🌀': HuudArtSpec('huud-signal:spiral', 'Spiral'),
    '⚗': HuudArtSpec('huud-signal:flask', 'Science flask'),
    '💠': HuudArtSpec('huud-signal:gem', 'Gem'),
    '🧩': HuudArtSpec('huud-signal:puzzle', 'Puzzle'),
    '🪬': HuudArtSpec('assets/images/huud_ui/hand.png', 'Hand talisman'),
    '🌅': HuudArtSpec('assets/images/huud_ui/sun.png', 'Morning'),
    '☀': HuudArtSpec('assets/images/huud_ui/sun.png', 'Daylight'),
    '🗳': HuudArtSpec('assets/images/huud_ui/shield.png', 'Review'),
    '⚖': HuudArtSpec('assets/images/huud_ui/shield.png', 'Review'),
    '🔎': HuudArtSpec('assets/images/huud_ui/shield.png', 'Review'),
    '🎯': HuudArtSpec('assets/images/huud_ui/shield.png', 'Review'),
    '🗂': HuudArtSpec('assets/images/huud_ui/shield.png', 'Review'),
    '✚': HuudArtSpec('huud-signal:puzzle', 'Cross'),
    '⬜': HuudArtSpec('assets/images/huud_ui/shield.png', 'Not selected'),
    '⏭': HuudArtSpec('assets/images/huud_ui/door.png', 'Skip'),
    '⚔': HuudArtSpec('assets/images/huud_ui/shield.png', 'Challenge'),
    '🎨': HuudArtSpec('assets/images/huud_ui/palette.png', 'Colours'),
    '🎪': HuudArtSpec('assets/images/huud_ui/party.png', 'Gathering'),
    '💡': HuudArtSpec('assets/images/huud_ui/bulb.png', 'Tip'),
    '📭': HuudArtSpec('assets/images/nav/messages_active.png', 'Inbox'),
    '🪙': HuudArtSpec('assets/images/huud_ui/coin.png', 'Coins'),
  };
  static HuudArtSpec? lookup(String token) => _tokens[normalize(token)];
  static bool containsArtwork(String text) =>
      text.characters.any((c) => lookup(c) != null);
  static String spoken(String text) => text.characters
      .map((c) => lookup(c) == null ? c : ' ${lookup(c)!.label} ')
      .join()
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
  static Iterable<HuudArtSpec> get all => _tokens.values;
}

/// App-supplied artwork only. User messages and photos retain their own content.
class HuudSymbol extends StatelessWidget {
  const HuudSymbol(this.token,
      {super.key, this.size = 24, this.decorative = false});
  final String token;
  final double size;
  final bool decorative;
  @override
  Widget build(BuildContext context) {
    final spec = HuudArt.lookup(token);
    return Semantics(
      label: decorative ? null : spec?.label ?? 'Huud',
      excludeSemantics: true,
      child: spec?.asset.startsWith('huud-signal:') == true
          ? HuudSignalArt(spec!.asset.substring(12), size: size)
          : Image.asset(
              spec?.asset ?? 'assets/images/nav/huud_active.png',
              key: ValueKey('huud-symbol-${HuudArt.normalize(token)}'),
              width: size,
              height: size,
              fit: BoxFit.contain,
              cacheWidth:
                  (size * (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1))
                      .ceil(),
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
            ),
    );
  }
}

/// Rich app copy with inline custom art. Plain labels follow Text's usual path;
/// Text's options retain wrapping, direction, scaling and accessible wording.
class HuudText extends Text {
  const HuudText(super.data,
      {super.key,
      this.artwork = true,
      super.style,
      super.strutStyle,
      super.textAlign,
      super.textDirection,
      super.locale,
      super.softWrap,
      super.overflow,
      super.textScaler,
      super.maxLines,
      super.semanticsLabel,
      super.textWidthBasis,
      super.textHeightBehavior,
      super.selectionColor});
  final bool artwork;
  @override
  Widget build(BuildContext context) {
    final value = data!;
    if (!artwork || !HuudArt.containsArtwork(value)) {
      return super.build(context);
    }
    final defaults = DefaultTextStyle.of(context);
    final resolved =
        style == null || style!.inherit ? defaults.style.merge(style) : style!;
    final fontSize = resolved.fontSize ?? 14;
    final scaler = textScaler ?? MediaQuery.textScalerOf(context);
    final spans = <InlineSpan>[];
    var plain = '';
    void flush() {
      if (plain.isNotEmpty) {
        spans.add(TextSpan(text: plain));
        plain = '';
      }
    }

    for (final character in value.characters) {
      if (HuudArt.lookup(character) == null) {
        plain += character;
      } else {
        flush();
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding:
                EdgeInsets.symmetric(horizontal: scaler.scale(fontSize) * .035),
            child: HuudSymbol(character,
                size: scaler.scale(fontSize) * 1.18, decorative: true),
          ),
        ));
      }
    }
    flush();
    return Text.rich(
      TextSpan(children: spans),
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel ?? HuudArt.spoken(value),
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    ).build(context);
  }
}
