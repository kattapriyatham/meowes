import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/features/settlements/settle_up_screen.dart';

class FriendDetailScreen extends ConsumerWidget {
  final String friendUserId;
  const FriendDetailScreen({super.key, required this.friendUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final me = client.auth.currentUser!.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Friend')),
      body: FutureBuilder(
        future: client.rpc('get_friend_balance', params: {
          'user_a': me,
          'user_b': friendUserId,
        }),
        builder: (context, snapshot) {
          final balance = (snapshot.data as num?)?.toDouble() ?? 0;
          return Column(
            children: [
              Text('₹${balance.toStringAsFixed(2)}'),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettleUpScreen(
                      toUser: friendUserId,
                      amountMinorUnits: (balance.abs() * 100).round(),
                    ),
                  ),
                ),
                child: const Text('Settle up'),
              ),
            ],
          );
        },
      ),
    );
  }
}
