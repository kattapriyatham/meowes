import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/models/friend_activity_item.dart';

void main() {
  test('FriendActivityItem.fromJson parses kind, net (numeric) and date', () {
    final item = FriendActivityItem.fromJson({
      'kind': 'group',
      'ref_id': 'g1',
      'name': 'Goa Trip',
      'net': -1400.00,
      'activity_date': '2026-07-20',
    });
    expect(item.kind, FriendActivityKind.group);
    expect(item.refId, 'g1');
    expect(item.name, 'Goa Trip');
    expect(item.net, -1400.00);
    expect(item.date, DateTime(2026, 7, 20));
  });

  test('FriendActivityItem.fromJson accepts net as a string (PostgREST numeric wire format)', () {
    final item = FriendActivityItem.fromJson({
      'kind': 'expense',
      'ref_id': 'e1',
      'name': 'Groceries',
      'net': '100.00',
      'activity_date': '2026-07-27',
    });
    expect(item.kind, FriendActivityKind.expense);
    expect(item.net, 100.00);
  });
}
