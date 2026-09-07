import 'dart:async';

import 'package:flutter/material.dart';

/// An [IconButton] for a one-shot async action: while [onPressed]'s future is
/// pending it shows a spinner in place of the icon and ignores further taps,
/// so row actions like Accept / Confirm can't be double-fired.
class AsyncIconButton extends StatefulWidget {
  final IconData icon;
  final Color? color;
  final String? tooltip;
  final FutureOr<void> Function()? onPressed;

  const AsyncIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.tooltip,
  });

  @override
  State<AsyncIconButton> createState() => _AsyncIconButtonState();
}

class _AsyncIconButtonState extends State<AsyncIconButton> {
  bool _running = false;

  Future<void> _handle() async {
    if (_running || widget.onPressed == null) return;
    final result = widget.onPressed!();
    if (result is! Future) return;
    setState(() => _running = true);
    try {
      await result;
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'meowes',
        context: ErrorDescription('during an AsyncIconButton tap'),
      ));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_running) {
      return SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: widget.color),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: widget.tooltip,
      icon: Icon(widget.icon, color: widget.color),
      onPressed: widget.onPressed == null ? null : _handle,
    );
  }
}
