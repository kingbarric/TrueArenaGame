import 'package:flutter/widgets.dart';

/// Where the share sheet should appear to come from. Current iOS won't open
/// the sheet without an anchor, so every share passes this: the widget at
/// [context] when it's laid out, else the top half of the screen.
Rect shareOrigin(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.attached && box.hasSize && !box.size.isEmpty) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  final size = MediaQuery.sizeOf(context);
  return Rect.fromLTWH(0, 0, size.width, size.height / 2);
}
