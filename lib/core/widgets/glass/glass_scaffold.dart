import 'package:flutter/material.dart';
import 'package:meowes_app/core/widgets/glass/glass_background.dart';

class GlassScaffold extends StatelessWidget {
  const GlassScaffold({super.key, required this.body, this.appBar, this.bottomDock});
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomDock;

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        extendBodyBehindAppBar: true,
        appBar: appBar,
        body: Stack(
          children: [
            Positioned.fill(child: body),
            if (bottomDock != null)
              Positioned(left: 0, right: 0, bottom: 0, child: bottomDock!),
          ],
        ),
      ),
    );
  }
}
