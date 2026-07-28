// lib/features/expenses/add_expense_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart' show friendRepositoryProvider;
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/models/expense_split.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/splitting/split_calculator.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  final String? groupId;
  final List<String> participantIds;
  final Expense? editing;
  final List<ExpenseSplit>? existingSplits;

  const AddExpenseScreen({
    super.key,
    this.groupId,
    required this.participantIds,
    this.editing,
    this.existingSplits,
  });

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  SplitType _splitType = SplitType.equal;
  late String _paidBy;
  final Map<String, TextEditingController> _percentControllers = {};
  final Map<String, double> _exactAmounts = {};
  late final Future<List<AppUser>> _profilesFuture;
  String _me = '';

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    final existingSplits = widget.existingSplits;

    _paidBy = widget.participantIds.isEmpty
        ? ''
        : (editing?.paidBy ?? widget.participantIds.first);
    final evenPercent = widget.participantIds.isEmpty
        ? '0'
        : (100 / widget.participantIds.length).toStringAsFixed(1);
    for (final id in widget.participantIds) {
      _percentControllers[id] = TextEditingController(text: evenPercent);
      _exactAmounts[id] = 0;
    }

    if (editing != null && existingSplits != null && existingSplits.isNotEmpty) {
      _descriptionController.text = editing.description;
      _amountController.text = (editing.amountMinorUnits / 100).toStringAsFixed(2);
      _splitType = SplitType.exact;
      for (final split in existingSplits) {
        _exactAmounts[split.userId] = split.shareAmountMinorUnits / 100;
        final pct = editing.amountMinorUnits == 0
            ? 0.0
            : split.shareAmountMinorUnits / editing.amountMinorUnits * 100;
        _percentControllers[split.userId]?.text = pct.toStringAsFixed(1);
      }
    }

    // Attached after any prefill above so setting .text programmatically
    // doesn't trigger _onAmountChanged and reset the just-restored exact
    // amounts back to an even split.
    _amountController.addListener(_onAmountChanged);

    _profilesFuture = widget.participantIds.isEmpty
        ? Future.value(<AppUser>[])
        : ref.read(friendRepositoryProvider).getPublicProfiles(widget.participantIds);
  }

  void _onAmountChanged() {
    final total = double.tryParse(_amountController.text) ?? 0;
    final even = widget.participantIds.isEmpty ? 0.0 : total / widget.participantIds.length;
    setState(() {
      for (final id in widget.participantIds) {
        _exactAmounts[id] = even;
      }
    });
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _descriptionController.dispose();
    _amountController.dispose();
    for (final c in _percentControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _totalAmount => double.tryParse(_amountController.text) ?? 0;

  double get _percentTotal => widget.participantIds.fold<double>(
        0,
        (sum, id) => sum + (double.tryParse(_percentControllers[id]!.text) ?? 0),
      );

  double get _exactTotal =>
      widget.participantIds.fold<double>(0, (sum, id) => sum + (_exactAmounts[id] ?? 0));

  bool get _canSave {
    if (_descriptionController.text.trim().isEmpty || _totalAmount <= 0) return false;
    if (_splitType == SplitType.percentage) {
      if (widget.participantIds.any((id) => double.tryParse(_percentControllers[id]!.text) == null)) {
        return false;
      }
      return (_percentTotal - 100).abs() < 0.01;
    }
    if (_splitType == SplitType.exact) {
      return (_exactTotal - _totalAmount).abs() < 0.01 && _computeExactSharesInPaise() != null;
    }
    return true;
  }

  Map<String, int>? _computeExactSharesInPaise() {
    final ids = widget.participantIds;
    final amountMinorUnits = (_totalAmount * 100).round();
    final result = <String, int>{};
    var allocated = 0;
    for (var i = 0; i < ids.length; i++) {
      if (i == ids.length - 1) {
        result[ids[i]] = amountMinorUnits - allocated;
      } else {
        final share = (_exactAmounts[ids[i]]! * 100).round();
        result[ids[i]] = share;
        allocated += share;
      }
    }
    if (result.values.any((v) => v < 0)) return null;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(expenseRepositoryProvider);
    _me = ref.watch(supabaseClientProvider).auth.currentUser!.id;
    final isEditing = widget.editing != null;

    if (widget.participantIds.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(isEditing ? 'Edit expense' : 'Add expense')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No participants to split this expense with yet.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit expense' : 'Add expense')),
      body: FutureBuilder<List<AppUser>>(
        future: _profilesFuture,
        builder: (context, snapshot) {
          final names = {for (final p in snapshot.data ?? <AppUser>[]) p.id: p.name};
          String nameOf(String id) => id == _me ? 'Me' : (names[id] ?? '...');

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 20),
              if (!isEditing) ...[
                const SectionHeader(title: 'Paid by'),
                const SizedBox(height: 8),
                for (final id in widget.participantIds)
                  RadioListTile<String>(
                    value: id,
                    groupValue: _paidBy,
                    onChanged: (v) => setState(() => _paidBy = v!),
                    title: Text(nameOf(id)),
                    activeColor: AppColors.coral,
                    contentPadding: EdgeInsets.zero,
                  ),
                const SizedBox(height: 12),
              ],
              const SectionHeader(title: 'Split between'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final id in widget.participantIds)
                    Chip(
                      avatar: AppAvatar(seed: id, label: nameOf(id), size: 24),
                      label: Text(nameOf(id)),
                      backgroundColor: Colors.white,
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Split type'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _SplitTypeTile(
                      label: 'Equal',
                      icon: Icons.balance,
                      color: AppColors.avatarPalette[4],
                      selected: _splitType == SplitType.equal,
                      onTap: () => setState(() => _splitType = SplitType.equal),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SplitTypeTile(
                      label: 'Percentage',
                      icon: Icons.percent,
                      color: AppColors.avatarPalette[1],
                      selected: _splitType == SplitType.percentage,
                      onTap: () => setState(() => _splitType = SplitType.percentage),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SplitTypeTile(
                      label: 'Exact',
                      icon: Icons.tune,
                      color: AppColors.avatarPalette[3],
                      selected: _splitType == SplitType.exact,
                      onTap: () => setState(() => _splitType = SplitType.exact),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_splitType == SplitType.percentage) ...[
                for (final id in widget.participantIds)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(child: Text(nameOf(id))),
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: _percentControllers[id],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(suffixText: '%'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  'Total: ${_percentTotal.toStringAsFixed(1)}% (needs to be 100%)',
                  style: TextStyle(
                    color: (_percentTotal - 100).abs() < 0.01 ? AppColors.owedText : AppColors.owingText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (_splitType == SplitType.exact) ...[
                for (final id in widget.participantIds)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(nameOf(id))),
                            Text('₹${(_exactAmounts[id] ?? 0).toStringAsFixed(2)}'),
                          ],
                        ),
                        Slider(
                          value: (_exactAmounts[id] ?? 0).clamp(0, _totalAmount == 0 ? 1 : _totalAmount),
                          min: 0,
                          max: _totalAmount == 0 ? 1 : _totalAmount,
                          activeColor: AppColors.coral,
                          onChanged: _totalAmount == 0
                              ? null
                              : (v) => setState(() => _exactAmounts[id] = v),
                        ),
                      ],
                    ),
                  ),
                Text(
                  'Remaining: ₹${(_totalAmount - _exactTotal).toStringAsFixed(2)}',
                  style: TextStyle(
                    color: (_totalAmount - _exactTotal).abs() < 0.01 ? AppColors.owedText : AppColors.owingText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canSave
                      ? () async {
                          final amountMinorUnits = (_totalAmount * 100).round();
                          final percentages = _splitType == SplitType.percentage
                              ? {
                                  for (final id in widget.participantIds)
                                    id: double.parse(_percentControllers[id]!.text),
                                }
                              : null;
                          final exactAmounts =
                              _splitType == SplitType.exact ? _computeExactSharesInPaise() : null;

                          if (isEditing) {
                            await repo.editExpense(
                              expenseId: widget.editing!.id,
                              description: _descriptionController.text.trim(),
                              amountMinorUnits: amountMinorUnits,
                              splitType: _splitType,
                              participantIds: widget.participantIds,
                              percentages: percentages,
                              exactAmounts: exactAmounts,
                            );
                          } else {
                            await repo.createExpense(
                              description: _descriptionController.text.trim(),
                              amountMinorUnits: amountMinorUnits,
                              groupId: widget.groupId,
                              paidBy: _paidBy,
                              splitType: _splitType,
                              participantIds: widget.participantIds,
                              percentages: percentages,
                              exactAmounts: exactAmounts,
                              expenseDate: DateTime.now(),
                            );
                          }
                          if (context.mounted) Navigator.of(context).pop();
                        }
                      : null,
                  child: Text(isEditing ? 'Save Changes' : 'Save Expense'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SplitTypeTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SplitTypeTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color : Colors.transparent, width: 2),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
