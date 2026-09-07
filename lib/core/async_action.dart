import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:meowes_app/core/supabase_client.dart';

/// Runs a one-shot mutating [action] with the feedback every button in the
/// app should have:
///
///  * on success — bumps [dataChangedTickerProvider] (so one-shot
///    `FutureBuilder` screens revealed by a pop re-fetch) and, if given,
///    shows [successMessage] in a SnackBar;
///  * on failure — shows an error SnackBar with a **Retry** action that
///    re-runs the same [action].
///
/// Returns `true` when [action] completed without throwing. Pair it with
/// [PillButton]'s async `onTap` so the button also shows a spinner and
/// blocks double-taps for the duration:
///
/// ```dart
/// PillButton(
///   label: 'Delete',
///   onTap: () async {
///     final ok = await runAction(
///       context, ref,
///       action: () => repo.deleteExpense(id),
///       successMessage: 'Expense deleted',
///     );
///     if (ok && context.mounted) Navigator.of(context).pop();
///   },
/// )
/// ```
Future<bool> runAction(
  BuildContext context,
  WidgetRef ref, {
  required Future<void> Function() action,
  String? successMessage,
  bool notifyData = true,
  String Function(Object error)? errorMessage,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (notifyData) notifyDataChanged(ref);
    if (successMessage != null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(successMessage)));
    }
    return true;
  } catch (error) {
    final text = errorMessage?.call(error) ?? _defaultMessage(error);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () {
              if (!context.mounted) return;
              runAction(
                context,
                ref,
                action: action,
                successMessage: successMessage,
                notifyData: notifyData,
                errorMessage: errorMessage,
              );
            },
          ),
        ),
      );
    return false;
  }
}

String _defaultMessage(Object error) {
  if (error is PostgrestException) return error.message;
  if (error is AuthException) return error.message;
  return "Something went wrong. Please try again.";
}
