// test/models/models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/models/settlement.dart';

void main() {
  test('AppUser round-trips through JSON', () {
    final user = AppUser(
      id: 'u1',
      name: 'Alex',
      avatarUrl: null,
      phoneNumber: '+911234567890',
    );
    final json = user.toJson();
    final restored = AppUser.fromJson(json);
    expect(restored.id, 'u1');
    expect(restored.phoneNumber, '+911234567890');
  });

  test('Expense fromJson handles nullable groupId and soft-delete fields', () {
    final expense = Expense.fromJson({
      'id': 'e1',
      'group_id': null,
      'paid_by': 'u1',
      'description': 'Coffee',
      'amount': '250.00',
      'currency': 'INR',
      'expense_date': '2026-07-27',
      'created_at': '2026-07-27T10:00:00Z',
      'created_by': 'u1',
      'edited_at': null,
      'edited_by': null,
      'deleted_at': null,
    });
    expect(expense.groupId, isNull);
    expect(expense.amountMinorUnits, 25000);
    expect(expense.isDeleted, isFalse);
  });

  test('Settlement fromJson parses status correctly', () {
    final settlement = Settlement.fromJson({
      'id': 's1',
      'group_id': null,
      'from_user': 'u1',
      'to_user': 'u2',
      'amount': '500.00',
      'status': 'pending_confirmation',
      'created_at': '2026-07-27T10:00:00Z',
      'confirmed_at': null,
    });
    expect(settlement.status, SettlementStatus.pendingConfirmation);
  });
}
