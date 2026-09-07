import 'package:flutter/material.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/home/home_screen.dart';
import 'package:meowes_app/features/friends/friends_screen.dart';
import 'package:meowes_app/features/groups/groups_screen.dart';
import 'package:meowes_app/features/activity/activity_screen.dart';
import 'package:meowes_app/features/pet/pet_home_screen.dart';

/// The signed-in app shell: an [IndexedStack] of the five tab screens with
/// the floating [GlassNavDock] overlaid at the bottom. Deliberately NOT a
/// [GlassScaffold] itself — each tab screen is already its own full
/// GlassScaffold (own GlassBackground + GlassAppBar), so wrapping this in
/// another one would double up the background/Scaffold.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  static const _tabs = [
    HomeScreen(),
    PetHomeScreen(),
    FriendsScreen(),
    GroupsScreen(),
    ActivityScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IndexedStack(index: _index, children: _tabs),
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: GlassNavDock(currentIndex: _index, onTap: (i) => setState(() => _index = i)),
        ),
      ],
    );
  }
}
