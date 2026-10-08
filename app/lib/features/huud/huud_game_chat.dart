import 'package:flutter/material.dart';
import '../../widgets/table_chat.dart';
import 'social_huud_controller.dart';
import 'social_huud_screen.dart';

/// A single expanded chat layer. Functional Word Bluff input stays match-scoped.
class HuudGameChat extends StatefulWidget {
  const HuudGameChat(
      {super.key, required this.controller, required this.gameChat});
  final SocialHuudController controller;
  final Widget gameChat;
  @override
  State<HuudGameChat> createState() => _HuudGameChatState();
}

class _HuudGameChatState extends State<HuudGameChat> {
  bool _game = true;
  @override
  Widget build(BuildContext context) {
    final structured = widget.controller.huud.gameType == 'wordbluff';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (structured)
        SegmentedButton<bool>(segments: const [
          ButtonSegment(value: true, label: Text('Game Chat')),
          ButtonSegment(value: false, label: Text('Huud Chat')),
        ], selected: {
          _game
        }, onSelectionChanged: (v) => setState(() => _game = v.first)),
      if (structured && _game)
        widget.gameChat
      else
        TextButton.icon(
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('Huud Chat'),
          onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              backgroundColor: Theme.of(context).colorScheme.surface,
              builder: (ctx) => Padding(
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(ctx).bottom),
                  child: SizedBox(
                      height: MediaQuery.sizeOf(ctx).height * .45,
                      child: HuudChat(controller: widget.controller)))),
        ),
    ]);
  }
}

TableChatPanel gameInteractionPanel(TableChatPanel w) => TableChatPanel(
      lines: w.lines,
      controller: w.controller,
      onSend: w.onSend,
      spectatorCount: w.spectatorCount,
      amSpectator: w.amSpectator,
      height: w.height,
      canSend: w.canSend,
      disabledHint: w.disabledHint,
      initiallyExpanded: w.initiallyExpanded,
      composerHint: w.composerHint,
      emptyHint: w.emptyHint,
      gameInteractionOnly: true,
    );
