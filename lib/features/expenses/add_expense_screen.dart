// lib/features/expenses/add_expense_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/async_action.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart' show friendRepositoryProvider;
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/models/expense_split.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/splitting/split_calculator.dart';

/// Accent used only for selection state (selected chip/tile border + check
/// badges) on this screen, matching the reference design's gold outline
/// style — distinct from the app's black-ink primary accent.
const _kGold = Color(0xFFC08B1E);

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
  late Set<String> _sharingIds;
  final Map<String, TextEditingController> _percentControllers = {};
  final Map<String, TextEditingController> _exactControllers = {};
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
    _sharingIds = Set.of(widget.participantIds);
    for (final id in widget.participantIds) {
      _percentControllers[id] = TextEditingController();
      _exactControllers[id] = TextEditingController();
    }

    if (editing != null && existingSplits != null && existingSplits.isNotEmpty) {
      _descriptionController.text = editing.description;
      _amountController.text = (editing.amountMinorUnits / 100).toStringAsFixed(2);
      _splitType = SplitType.exact;
      _sharingIds = existingSplits.map((s) => s.userId).toSet();
      for (final split in existingSplits) {
        final amount = split.shareAmountMinorUnits / 100;
        _exactControllers[split.userId]?.text = amount.round().toString();
        final pct = editing.amountMinorUnits == 0
            ? 0.0
            : split.shareAmountMinorUnits / editing.amountMinorUnits * 100;
        _percentControllers[split.userId]?.text = pct.toStringAsFixed(1);
      }
    } else {
      _resetSplitsToEven();
    }

    // Attached after any prefill above so setting .text programmatically
    // doesn't trigger _onAmountChanged and reset the just-restored splits.
    _amountController.addListener(_onAmountChanged);

    _profilesFuture = widget.participantIds.isEmpty
        ? Future.value(<AppUser>[])
        : ref.read(friendRepositoryProvider).getPublicProfiles(widget.participantIds);
  }

  void _onAmountChanged() => _resetSplitsToEven();

  /// Distributes the current total evenly across the currently-sharing
  /// participants for both the exact and percentage controllers. Called
  /// whenever the amount changes or the sharing set changes, so switching
  /// split type never shows stale numbers from a different total/group.
  void _resetSplitsToEven() {
    final total = double.tryParse(_amountController.text) ?? 0;
    final ids = _sharingIds.toList();
    final evenAmount = ids.isEmpty ? 0.0 : (total / ids.length).roundToDouble();
    final evenPercent = ids.isEmpty ? 0.0 : 100 / ids.length;
    setState(() {
      for (final id in widget.participantIds) {
        final sharing = _sharingIds.contains(id);
        _exactControllers[id]!.text = sharing ? evenAmount.round().toString() : '0';
        _percentControllers[id]!.text = sharing ? evenPercent.toStringAsFixed(1) : '0';
      }
    });
  }

  void _setSharing(String id, bool sharing) {
    setState(() {
      if (sharing) {
        _sharingIds.add(id);
      } else {
        if (_sharingIds.length <= 1) return;
        _sharingIds.remove(id);
      }
    });
    _resetSplitsToEven();
  }

  void _toggleSelectAll() {
    setState(() {
      if (_sharingIds.length == widget.participantIds.length) {
        _sharingIds = {widget.participantIds.first};
      } else {
        _sharingIds = Set.of(widget.participantIds);
      }
    });
    _resetSplitsToEven();
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _descriptionController.dispose();
    _amountController.dispose();
    for (final c in _percentControllers.values) {
      c.dispose();
    }
    for (final c in _exactControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _totalAmount => double.tryParse(_amountController.text) ?? 0;

  double get _percentTotal =>
      _sharingIds.fold<double>(0, (sum, id) => sum + (double.tryParse(_percentControllers[id]!.text) ?? 0));

  double get _exactTotal =>
      _sharingIds.fold<double>(0, (sum, id) => sum + (double.tryParse(_exactControllers[id]!.text) ?? 0));

  bool get _canSave {
    if (_descriptionController.text.trim().isEmpty || _totalAmount <= 0) return false;
    if (_sharingIds.isEmpty) return false;
    if (_splitType == SplitType.percentage) {
      if (_sharingIds.any((id) => double.tryParse(_percentControllers[id]!.text) == null)) {
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
    final ids = _sharingIds.toList();
    final amountMinorUnits = (_totalAmount * 100).round();
    final result = <String, int>{};
    var allocated = 0;
    for (var i = 0; i < ids.length; i++) {
      if (i == ids.length - 1) {
        result[ids[i]] = amountMinorUnits - allocated;
      } else {
        final share = ((double.tryParse(_exactControllers[ids[i]]!.text) ?? 0) * 100).round();
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
    final t = Theme.of(context).extension<GlassTokens>()!;
    _me = ref.watch(supabaseClientProvider).auth.currentUser!.id;
    final isEditing = widget.editing != null;

    if (widget.participantIds.isEmpty) {
      return GlassScaffold(
        appBar: GlassAppBar(title: isEditing ? 'Edit expense' : 'Add expense'),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No participants to split this expense with yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary),
              ),
            ),
          ),
        ),
      );
    }

    return GlassScaffold(
      appBar: GlassAppBar(title: isEditing ? 'Edit expense' : 'Add expense'),
      body: SafeArea(
        child: FutureBuilder<List<AppUser>>(
          future: _profilesFuture,
          builder: (context, snapshot) {
            final names = {for (final p in snapshot.data ?? <AppUser>[]) p.id: p.name};
            String nameOf(String id) => id == _me ? 'Me' : (names[id] ?? '...');

            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SoftCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _descriptionController,
                                decoration: const InputDecoration(labelText: 'Description'),
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _amountController,
                                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹'),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        if (!isEditing) ...[
                          const SizedBox(height: 20),
                          const SectionHeader(title: 'Who paid?'),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 52,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: widget.participantIds.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 10),
                              itemBuilder: (context, i) {
                                final id = widget.participantIds[i];
                                return _PayerChip(
                                  selected: _paidBy == id,
                                  name: nameOf(id),
                                  seed: id,
                                  onTap: () => setState(() => _paidBy = id),
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        const SectionHeader(title: 'Split type'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _SplitTypeTile(
                                label: 'Equal',
                                icon: Icons.balance,
                                selected: _splitType == SplitType.equal,
                                onTap: () => setState(() => _splitType = SplitType.equal),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _SplitTypeTile(
                                label: 'Percentage',
                                icon: Icons.percent,
                                selected: _splitType == SplitType.percentage,
                                onTap: () => setState(() => _splitType = SplitType.percentage),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _SplitTypeTile(
                                label: 'Exact',
                                icon: Icons.tune,
                                selected: _splitType == SplitType.exact,
                                onTap: () => setState(() => _splitType = SplitType.exact),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Expanded(child: SectionHeader(title: "Who's sharing?")),
                            GestureDetector(
                              onTap: _toggleSelectAll,
                              child: Text(
                                _sharingIds.length == widget.participantIds.length
                                    ? 'Clear'
                                    : 'Select all',
                                style: const TextStyle(color: _kGold, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _SharingSplitCard(
                          splitType: _splitType,
                          participantIds: widget.participantIds,
                          sharingIds: _sharingIds,
                          nameOf: nameOf,
                          totalAmount: _totalAmount,
                          exactControllers: _exactControllers,
                          percentControllers: _percentControllers,
                          exactTotal: _exactTotal,
                          percentTotal: _percentTotal,
                          onToggleSharing: _setSharing,
                          onExactChanged: (_) => setState(() {}),
                          onPercentChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: PillButton(
                    label: isEditing ? 'Save Changes' : 'Save Expense',
                    primary: true,
                    onTap: _canSave
                        ? () async {
                            final amountMinorUnits = (_totalAmount * 100).round();
                            final sharingIds = _sharingIds.toList();
                            final percentages = _splitType == SplitType.percentage
                                ? {
                                    for (final id in sharingIds)
                                      id: double.parse(_percentControllers[id]!.text),
                                  }
                                : null;
                            final exactAmounts =
                                _splitType == SplitType.exact ? _computeExactSharesInPaise() : null;

                            final ok = await runAction(
                              context,
                              ref,
                              action: () async {
                                if (isEditing) {
                                  await repo.editExpense(
                                    expenseId: widget.editing!.id,
                                    description: _descriptionController.text.trim(),
                                    amountMinorUnits: amountMinorUnits,
                                    splitType: _splitType,
                                    participantIds: sharingIds,
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
                                    participantIds: sharingIds,
                                    percentages: percentages,
                                    exactAmounts: exactAmounts,
                                    expenseDate: DateTime.now(),
                                  );
                                }
                              },
                              successMessage: isEditing ? 'Expense updated' : 'Expense added',
                            );
                            if (ok && context.mounted) Navigator.of(context).pop();
                          }
                        : null,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SplitTypeTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SplitTypeTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final fg = selected ? _kGold : t.textPrimary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: t.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? _kGold : t.glassBorder, width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fg, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact selectable avatar+name pill used in the horizontally-scrolling
/// "Who paid?" row.
class _PayerChip extends StatelessWidget {
  final bool selected;
  final String name;
  final String seed;
  final VoidCallback onTap;

  const _PayerChip({
    required this.selected,
    required this.name,
    required this.seed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: t.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _kGold : t.glassBorder, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppAvatar(seed: seed, label: name, size: 26),
            const SizedBox(width: 8),
            Text(
              name,
              style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              const _CheckBadge(),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small filled gold circle with a white checkmark — the selected-state
/// indicator used by [_PayerChip] and [_SharingRow].
class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: const BoxDecoration(color: _kGold, shape: BoxShape.circle),
      child: const Icon(Icons.check, color: Colors.white, size: 14),
    );
  }
}

/// Merged "who's sharing + how much" card: one row per participant with an
/// avatar, name, their amount (read-only for Equal, editable for
/// Exact/Percentage), and a trailing check badge that toggles whether they
/// share the expense at all. Unchecked participants show a blank amount
/// slot instead of a second, separate summary list.
class _SharingSplitCard extends StatelessWidget {
  final SplitType splitType;
  final List<String> participantIds;
  final Set<String> sharingIds;
  final String Function(String id) nameOf;
  final double totalAmount;
  final Map<String, TextEditingController> exactControllers;
  final Map<String, TextEditingController> percentControllers;
  final double exactTotal;
  final double percentTotal;
  final void Function(String id, bool sharing) onToggleSharing;
  final ValueChanged<String> onExactChanged;
  final ValueChanged<String> onPercentChanged;

  const _SharingSplitCard({
    required this.splitType,
    required this.participantIds,
    required this.sharingIds,
    required this.nameOf,
    required this.totalAmount,
    required this.exactControllers,
    required this.percentControllers,
    required this.exactTotal,
    required this.percentTotal,
    required this.onToggleSharing,
    required this.onExactChanged,
    required this.onPercentChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final isExact = splitType == SplitType.exact;
    final isEqual = splitType == SplitType.equal;
    final equalShares = isEqual
        ? SplitCalculator.calculate(
            totalMinorUnits: (totalAmount * 100).round(),
            type: SplitType.equal,
            participantIds: sharingIds.toList(),
          )
        : const <String, int>{};

    final balanced = isExact ? (exactTotal - totalAmount).abs() < 0.01 : (percentTotal - 100).abs() < 0.01;
    final progress = isExact
        ? (totalAmount <= 0 ? 0.0 : (exactTotal / totalAmount).clamp(0, 1).toDouble())
        : (percentTotal / 100).clamp(0, 1).toDouble();
    final statusColor = balanced ? t.positive : t.negative;
    final statusText = balanced
        ? 'Perfect! All set'
        : (isExact
            ? 'Remaining: ₹${(totalAmount - exactTotal).toStringAsFixed(2)}'
            : 'Total: ${percentTotal.toStringAsFixed(1)}% (needs to be 100%)');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < participantIds.length; i++) ...[
                if (i > 0) Divider(height: 1, color: t.glassBorder, indent: 16, endIndent: 16),
                Builder(builder: (context) {
                  final id = participantIds[i];
                  final checked = sharingIds.contains(id);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        AppAvatar(seed: id, label: nameOf(id), size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(nameOf(id), style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600)),
                        ),
                        SizedBox(
                          width: 90,
                          child: !checked
                              ? null
                              : (isEqual
                                  ? Text(
                                      '₹${((equalShares[id] ?? 0) / 100).toStringAsFixed(2)}',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700),
                                    )
                                  : TextField(
                                      controller: isExact ? exactControllers[id] : percentControllers[id],
                                      keyboardType: isExact
                                          ? TextInputType.number
                                          : const TextInputType.numberWithOptions(decimal: true),
                                      textAlign: TextAlign.right,
                                      decoration: InputDecoration(
                                        prefixText: isExact ? '₹' : null,
                                        suffixText: isExact ? null : '%',
                                      ),
                                      onChanged: isExact ? onExactChanged : onPercentChanged,
                                    )),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => onToggleSharing(id, !checked),
                          child: checked
                              ? const _CheckBadge()
                              : Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: t.glassBorder, width: 2),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
        if (!isEqual) ...[
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: t.glassBorder,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }
}
