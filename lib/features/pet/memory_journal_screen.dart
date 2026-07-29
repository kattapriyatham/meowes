import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/models/pet_memory.dart';
import 'package:meowes_app/repositories/pet_repository.dart';

class MemoryJournalScreen extends ConsumerWidget {
  const MemoryJournalScreen({super.key});

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final repo = ref.watch(petRepositoryProvider);

    return GlassScaffold(
      appBar: const GlassAppBar(title: 'Memories'),
      body: FutureBuilder<List<PetMemory>>(
        future: repo.getMemories(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SkeletonLoader();
          }
          final memories = snapshot.data!;
          if (memories.isEmpty) {
            return const EmptyStateBox(
              icon: Icons.menu_book_outlined,
              message: 'No memories yet — spend coins on an activity to start your journal',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: memories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final memory = memories[i];
              return SoftCard(
                key: ValueKey(memory.id),
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Hero(
                      tag: 'activity-image-${memory.activityId}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          memory.imageAsset,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) => Container(
                            width: 64,
                            height: 64,
                            color: t.textPrimary.withValues(alpha: 0.05),
                            alignment: Alignment.center,
                            child: Icon(Icons.photo_outlined, color: t.textMuted),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(memory.activityName,
                              style: TextStyle(
                                  color: t.textPrimary,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(memory.caption,
                              style: TextStyle(color: t.textSecondary, fontSize: 13)),
                          const SizedBox(height: 6),
                          Text(_formatDate(memory.completedAt),
                              style: TextStyle(color: t.textMuted, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
