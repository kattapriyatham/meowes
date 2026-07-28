// PostgREST returns numeric columns (share_amount) as JSON numbers, not
// strings, so parse defensively — same fix as Expense.amount / Settlement.amount.
int _parseShareMinorUnits(dynamic shareAmount) {
  final value = shareAmount is num ? shareAmount : double.parse(shareAmount as String);
  return (value * 100).round();
}

class ExpenseSplit {
  final String expenseId;
  final String userId;
  final int shareAmountMinorUnits;

  ExpenseSplit({
    required this.expenseId,
    required this.userId,
    required this.shareAmountMinorUnits,
  });

  factory ExpenseSplit.fromJson(Map<String, dynamic> json) => ExpenseSplit(
        expenseId: json['expense_id'] as String,
        userId: json['user_id'] as String,
        shareAmountMinorUnits: _parseShareMinorUnits(json['share_amount']),
      );

  Map<String, dynamic> toJson() => {
        'expense_id': expenseId,
        'user_id': userId,
        'share_amount': (shareAmountMinorUnits / 100).toStringAsFixed(2),
      };
}
