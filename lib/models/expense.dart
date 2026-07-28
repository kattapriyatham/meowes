int _parseAmountMinorUnits(dynamic amount) {
  final value = amount is num ? amount : double.parse(amount as String);
  return (value * 100).round();
}

class Expense {
  final String id;
  final String? groupId;
  final String paidBy;
  final String description;
  final int amountMinorUnits;
  final String currency;
  final DateTime expenseDate;
  final DateTime createdAt;
  final String createdBy;
  final DateTime? editedAt;
  final String? editedBy;
  final DateTime? deletedAt;

  Expense({
    required this.id,
    required this.groupId,
    required this.paidBy,
    required this.description,
    required this.amountMinorUnits,
    required this.currency,
    required this.expenseDate,
    required this.createdAt,
    required this.createdBy,
    this.editedAt,
    this.editedBy,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null;

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'] as String,
        groupId: json['group_id'] as String?,
        paidBy: json['paid_by'] as String,
        description: json['description'] as String,
        amountMinorUnits: _parseAmountMinorUnits(json['amount']),
        currency: json['currency'] as String,
        expenseDate: DateTime.parse(json['expense_date'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        createdBy: json['created_by'] as String,
        editedAt: json['edited_at'] == null
            ? null
            : DateTime.parse(json['edited_at'] as String),
        editedBy: json['edited_by'] as String?,
        deletedAt: json['deleted_at'] == null
            ? null
            : DateTime.parse(json['deleted_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'group_id': groupId,
        'paid_by': paidBy,
        'description': description,
        'amount': (amountMinorUnits / 100).toStringAsFixed(2),
        'currency': currency,
        'expense_date': expenseDate.toIso8601String().split('T').first,
        'created_by': createdBy,
      };
}
