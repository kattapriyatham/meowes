import 'package:flutter/material.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/glass/glass_background.dart';

/// A shared detail-page shell with an illustrated hero and a sheet that
/// expands before its contents begin scrolling.
class DetailHeroScaffold extends StatelessWidget {
  const DetailHeroScaffold({
    super.key,
    required this.heroAsset,
    required this.heroImageKey,
    required this.sheetKey,
    required this.title,
    required this.child,
    this.floatingActionButton,
    this.actionBuilders = const [],
  });

  final String heroAsset;
  final Key heroImageKey;
  final Key sheetKey;
  final String title;
  final Widget child;
  final Widget? floatingActionButton;
  final List<WidgetBuilder> actionBuilders;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                heroAsset,
                key: heroImageKey,
                excludeFromSemantics: true,
                fit: BoxFit.cover,
                alignment: Alignment.bottomCenter,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.08),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.10),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  children: [
                    Material(
                      color: Colors.white.withValues(alpha: 0.92),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: 'Back',
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: AppColors.textDark,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    ...actionBuilders.map((builder) => builder(context)),
                  ],
                ),
              ),
            ),
            DraggableScrollableSheet(
              initialChildSize: 0.50,
              minChildSize: 0.50,
              maxChildSize: 1,
              snap: true,
              snapSizes: const [0.50, 1],
              builder: (context, scrollController) => Container(
                key: sheetKey,
                decoration: BoxDecoration(
                  color: t.cardColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(30),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: t.cardShadow,
                      blurRadius: 26,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: true,
                  bottom: false,
                  child: Stack(
                    children: [
                      CustomScrollView(
                        controller: scrollController,
                        slivers: [
                          SliverToBoxAdapter(
                            child: Center(
                              child: Container(
                                width: 44,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 18),
                                decoration: BoxDecoration(
                                  color: t.textMuted.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 56, 20, 132),
                            sliver: SliverToBoxAdapter(child: child),
                          ),
                        ],
                      ),
                      Positioned(
                        top: 22,
                        left: 0,
                        right: 0,
                        child: _DetailSheetToolbar(
                          title: title,
                          actionBuilders: actionBuilders,
                        ),
                      ),
                      if (floatingActionButton != null)
                        Positioned(
                          right: 20,
                          bottom: 20,
                          child: floatingActionButton!,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailSheetToolbar extends StatelessWidget {
  const _DetailSheetToolbar({
    required this.title,
    required this.actionBuilders,
  });

  final String title;
  final List<WidgetBuilder> actionBuilders;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Container(
      key: const Key('detail-sheet-toolbar'),
      color: t.cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...actionBuilders.map((builder) => builder(context)),
        ],
      ),
    );
  }
}
