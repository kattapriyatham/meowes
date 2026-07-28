enum SettlementStatus { pendingConfirmation, confirmed }

int _parseAmountMinorUnits(dynamic amount) {
  final value = amount is num ? amount : double.parse(amount as String);
  return (value * 100).round();
}

class Settlement {
  final String id;
  final String? groupId;
  final String fromUser;
  final String toUser;
  final int amountMinorUnits;
  final SettlementStatus status;
  final DateTime createdAt;
  final DateTime? confirmedAt;

  Settlement({
    required this.id,
    required this.groupId,
    required this.fromUser,
    required this.toUser,
    required this.amountMinorUnits,
    required this.status,
    required this.createdAt,
    this.confirmedAt,
  });

  factory Settlement.fromJson(Map<String, dynamic> json) => Settlement(
        id: json['id'] as String,
        groupId: json['group_id'] as String?,
        fromUser: json['from_user'] as String,
        toUser: json['to_user'] as String,
        amountMinorUnits: _parseAmountMinorUnits(json['amount']),
        status: (json['status'] as String) == 'confirmed'
            ? SettlementStatus.confirmed
            : SettlementStatus.pendingConfirmation,
        createdAt: DateTime.parse(json['created_at'] as String),
        confirmedAt: json['confirmed_at'] == null
            ? null
            : DateTime.parse(json['confirmed_at'] as String),
      );
}
