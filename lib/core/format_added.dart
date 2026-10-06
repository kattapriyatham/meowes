const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "5 Sep, 2:30 PM" in local time (year appended when not the current year).
String formatAdded(DateTime when, {DateTime? now}) {
  final d = when.toLocal();
  final n = now ?? DateTime.now();
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final period = d.hour < 12 ? 'AM' : 'PM';
  final year = d.year == n.year ? '' : ' ${d.year}';
  return '${d.day} ${_months[d.month - 1]}$year, $hour12:$minute $period';
}
