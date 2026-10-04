import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Gives every displayed HUUD code the same tap-to-copy interaction.
class CopyableHuudCode extends StatelessWidget {
  const CopyableHuudCode({
    super.key,
    required this.code,
    required this.child,
  });

  final String code;
  final Widget child;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        duration: Duration(milliseconds: 1500),
        content: Text('Copied'),
      ));
  }

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Copy huud code',
        child: Semantics(
          button: true,
          label: 'Copy huud code $code',
          child: InkWell(
            key: ValueKey('copy-huud-code-$code'),
            borderRadius: BorderRadius.circular(6),
            onTap: () => _copy(context),
            child: child,
          ),
        ),
      );
}
