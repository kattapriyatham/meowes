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
        shareAmountMinorUnits:
            (double.parse(json['share_amount'] as String) * 100).round(),
      );

  Map<String, dynamic> toJson() => {
        'expense_id': expenseId,
        'user_id': userId,
        'share_amount': (shareAmountMinorUnits / 100).toStringAsFixed(2),
      };
}
