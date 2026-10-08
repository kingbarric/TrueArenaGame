import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/app_state.dart';
import '../core/models.dart';

class CancelHuudButton extends StatefulWidget {
  const CancelHuudButton({super.key, required this.room});
  final RoomView room;
  @override
  State<CancelHuudButton> createState() => _CancelHuudButtonState();
}

class _CancelHuudButtonState extends State<CancelHuudButton> {
  bool _busy = false;
  Future<void> _cancel() async {
    setState(() => _busy = true);
    final app = AppScope.of(context);
    try {
      await app.api.delete('/rooms/${widget.room.id}');
      await app.clearActiveRoom(widget.room.id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error is ApiException
                ? error.message
                : 'Could not cancel the Huud')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.room.status != 'lobby' ||
        widget.room.hostId != AppScope.of(context).user?.id) {
      return const SizedBox.shrink();
    }
    return TextButton(
      key: const ValueKey('cancel-huud'),
      onPressed: _busy ? null : _cancel,
      child: Text(_busy ? 'Cancelling…' : 'Cancel Huud',
          style: const TextStyle(fontSize: 12)),
    );
  }
}
