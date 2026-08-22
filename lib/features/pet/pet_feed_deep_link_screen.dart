import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/pet/feed_flow_screen.dart';
import 'package:meowes_app/models/food.dart';
import 'package:meowes_app/repositories/pet_repository.dart';

/// Pushed when a `pet_hungry` push notification is tapped (see
/// `_openFeedFlow` in `lib/main.dart`). `FeedFlowScreen` needs an
/// already-loaded `Pet`, but the tap handler runs outside the widget
/// tree with no `ref` available to fetch one — this screen bridges that
/// gap with a brief loading spinner, then replaces itself with the real
/// feed screen, food highlighted.
class PetFeedDeepLinkScreen extends ConsumerStatefulWidget {
  const PetFeedDeepLinkScreen({super.key, this.foodKey});
  final String? foodKey;

  @override
  ConsumerState<PetFeedDeepLinkScreen> createState() => _PetFeedDeepLinkScreenState();
}

class _PetFeedDeepLinkScreenState extends ConsumerState<PetFeedDeepLinkScreen> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pet = await ref.read(petRepositoryProvider).getOrCreatePet();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FeedFlowScreen(pet: pet, highlightFood: foodTypeFromKey(widget.foodKey)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const GlassScaffold(body: Center(child: CircularProgressIndicator()));
  }
}
