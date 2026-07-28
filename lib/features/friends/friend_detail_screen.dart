// lib/features/friends/friend_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/expenses/add_expense_screen.dart';
import 'package:meowes_app/features/expenses/expense_detail_screen.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/features/settlements/settle_up_screen.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/repositories/expense_repository.dart';

class FriendDetailScreen extends ConsumerWidget {
  final String friendUserId;
  const FriendDetailScreen({super.key, required this.friendUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final expenseRepo = ref.watch(expenseRepositoryProvider);
    final friendRepo = ref.watch(friendRepositoryProvider);
    final me = client.auth.currentUser!.id;
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<List<AppUser>>(
          future: friendRepo.getPublicProfiles([friendUserId]),
          builder: (context, snapshot) {
            final name = snapshot.data?.isNotEmpty == true ? snapshot.data!.first.name : null;
            return Text(name ?? 'Friend');
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: FutureBuilder(
          future: client.rpc('get_friend_balance', params: {
            'user_a': me,
            'user_b': friendUserId,
          }),
          builder: (context, snapshot) {
            final balance = (snapshot.data as num?)?.toDouble() ?? 0;
            // get_friend_balance(me, friend) is positive when the friend owes
            // me, negative when I owe the friend. Settling here means "I paid
            // this" (markPaid always records from_user = me), so the button
            // only makes sense when I'm the one who owes — offering it when
            // the friend owes me would record a payment in the wrong direction.
            final iOwe = balance < -0.005;
            return ListView(
              children: [
                BalanceSummaryCard(balance: balance),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AddExpenseScreen(
                              participantIds: [me, friendUserId],
                            ),
                          ),
                        ),
                        child: const Text('Add Expense'),
                      ),
                    ),
                    if (iOwe) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppOutlinedButton(
                          label: 'Settle Up',
                          color: AppColors.coral,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SettleUpScreen(
                                toUser: friendUserId,
                                amountMinorUnits: (balance.abs() * 100).round(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
                const SectionHeader(title: 'Expense history'),
                const SizedBox(height: 12),
                FutureBuilder<List<Expense>>(
                  future: expenseRepo.getSharedExpenses(friendUserId),
                  builder: (context, expenseSnapshot) {
                    final expenses = expenseSnapshot.data ?? [];
                    if (expenses.isEmpty) {
                      return const EmptyStateBox(
                        icon: Icons.receipt_long_outlined,
                        message: 'No expenses with this friend yet.',
                      );
                    }
                    return Column(
                      children: [
                        for (final e in expenses) ...[
                          AppCard(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => ExpenseDetailScreen(expense: e)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    e.description,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                ),
                                Text(
                                  '₹${(e.amountMinorUnits / 100).toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
