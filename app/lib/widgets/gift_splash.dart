import 'dart:async';

import 'package:flutter/material.dart';

/// A coin gift arriving: a small card that slides into the top corner for a
/// few seconds, over whatever you're doing — a game included — and lets
/// every tap through, so it never covers the page or gets in the way.
class GiftSplashHost extends StatefulWidget {
  const GiftSplashHost({super.key, required this.gifts, required this.child});

  /// `{fromName, coins}` for each gift that arrives.
  final Stream<Map<String, dynamic>> gifts;
  final Widget child;

  @override
  State<GiftSplashHost> createState() => _GiftSplashHostState();
}

class _GiftSplashHostState extends State<GiftSplashHost> {
  StreamSubscription<Map<String, dynamic>>? _sub;
  Map<String, dynamic>? _showing;
  Timer? _hide;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.gifts.listen(_show);
  }

  @override
  void didUpdateWidget(covariant GiftSplashHost old) {
    super.didUpdateWidget(old);
    if (old.gifts != widget.gifts) {
      _sub?.cancel();
      _sub = widget.gifts.listen(_show);
    }
  }

  void _show(Map<String, dynamic> gift) {
    if (!mounted) return;
    setState(() {
      _showing = gift;
      _visible = true;
    });
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 3200), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gift = _showing;
    return Stack(children: [
      widget.child,
      if (gift != null)
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          right: 10,
          child: IgnorePointer(
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutBack,
              offset: _visible ? Offset.zero : const Offset(1.3, 0),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: _visible ? 1 : 0,
                child: _GiftCard(fromName: '${gift['fromName'] ?? 'Someone'}', coins: (gift['coins'] as num?)?.toInt() ?? 3),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _GiftCard extends StatelessWidget {
  const _GiftCard({required this.fromName, required this.coins});
  final String fromName;
  final int coins;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('gift-splash'),
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 230),
        padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xffffc233), Color(0xffff8a1f)]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xff241708), width: 1.6),
          boxShadow: [BoxShadow(color: const Color(0xffff8a1f).withValues(alpha: 0.55), blurRadius: 16)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('🎁', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 8),
          Flexible(
            child: Text('$fromName sent you $coins coins!',
                maxLines: 2,
                style: const TextStyle(color: Color(0xff241708), fontWeight: FontWeight.w900, fontSize: 13.5)),
          ),
        ]),
      ),
    );
  }
}
