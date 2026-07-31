import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Always on: the glass blur effect is permanently disabled in favor of
// solid surfaces. No UI exposes a toggle for this anymore.
final reduceTransparencyProvider = StateProvider<bool>((ref) => true);

bool _platformReduceTransparency(BuildContext context) {
  final mq = MediaQuery.maybeOf(context);
  if (mq == null) return false;
  try {
    // Available on recent Flutter; guarded for older SDKs.
    return (mq as dynamic).reduceTransparency as bool? ?? false;
  } catch (_) {
    return false;
  }
}

bool glassDisabled(BuildContext context, {required bool userReduceTransparency}) =>
    userReduceTransparency || _platformReduceTransparency(context);

bool motionReduced(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;
