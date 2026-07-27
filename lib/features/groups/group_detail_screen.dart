import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/features/settlements/settle_up_screen.dart';

class GroupDetailScreen extends ConsumerWidget {
  final String groupId;
  const GroupDetailScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Group')),
      body: FutureBuilder(
        future: client.rpc('get_group_debts', params: {'target_group_id': groupId}),
        builder: (context, snapshot) {
          final debts = (snapshot.data as List<dynamic>?) ?? [];
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Smart settle suggestions'),
              ),
              for (final d in debts)
                ListTile(
                  title: Text('${d['from_user']} owes ${d['to_user']}'),
                  trailing: Text('₹${d['amount']}'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettleUpScreen(
                        toUser: d['to_user'] as String,
                        amountMinorUnits:
                            (double.parse(d['amount'].toString()) * 100).round(),
                        groupId: groupId,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
