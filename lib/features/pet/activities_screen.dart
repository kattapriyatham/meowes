// lib/features/pet/activities_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/pet/memory_journal_screen.dart';
import 'package:meowes_app/models/activity.dart';
import 'package:meowes_app/models/pet.dart';
import 'package:meowes_app/repositories/pet_repository.dart';

class ActivitiesScreen extends ConsumerStatefulWidget {
  const ActivitiesScreen({super.key});

  @override
  ConsumerState<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends ConsumerState<ActivitiesScreen> {
  late Future<List<Activity>> _activitiesFuture;
  int _coins = 0;
  bool _redeeming = false;

  @override
  void initState() {
    super.initState();
    _activitiesFuture = ref.read(petRepositoryProvider).getTodaysActivities();
    _loadCoins();
  }

  Future<void> _loadCoins() async {
    final pet = await ref.read(petRepositoryProvider).getOrCreatePet();
    if (mounted) setState(() => _coins = pet.coins);
  }

  Future<void> _redeem(Activity activity) async {
    if (_redeeming) return;
    setState(() => _redeeming = true);
    try {
      final memory = await ref
          .read(petRepositoryProvider)
          .redeemActivity(activity.id);
      if (!mounted) return;
      setState(() => _coins -= activity.coinCost);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(memory.activityName),
          content: Text(memory.caption),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Nice'),
            ),
          ],
        ),
      );
    } on InsufficientCoinsException {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Not enough coins for this activity yet'),
          ),
        );
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;

    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Activities',
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MemoryJournalScreen()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                '$_coins coins',
                style: TextStyle(color: t.textSecondary),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<Activity>>(
          future: _activitiesFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SkeletonLoader();
            }
            final activities = snapshot.data!;
            if (activities.isEmpty) {
              return const EmptyStateBox(
                icon: Icons.pets,
                message: 'No activities available right now',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: activities.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final activity = activities[i];
                final affordable = _coins >= activity.coinCost;
                return Opacity(
                  opacity: affordable ? 1 : 0.6,
                  child: SoftCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Hero(
                          tag: 'activity-image-${activity.id}',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              activity.imageAsset,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) =>
                                  Container(
                                    width: 64,
                                    height: 64,
                                    color: t.textPrimary.withValues(
                                      alpha: 0.08,
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.image_outlined,
                                      color: t.textSecondary,
                                    ),
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                activity.name,
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                activity.category,
                                style: TextStyle(
                                  color: t.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PillButton(
                          label: '${activity.coinCost}',
                          primary: affordable,
                          onTap: (_redeeming || !affordable)
                              ? null
                              : () => _redeem(activity),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
