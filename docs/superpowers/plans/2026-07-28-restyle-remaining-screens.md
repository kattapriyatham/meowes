# Restyle Remaining Screens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the Home screen's warm cream/coral design system (`lib/core/app_theme.dart`) to the remaining 9 existing screens, via a small shared widget library, and make Home's friend/group tiles tappable into the (now-restyled) detail screens.

**Architecture:** Promote the four presentation patterns Home already duplicates (`AppCard`, `AppAvatar`, `BalanceAmount`/`BalanceSummaryCard`, `EmptyStateBox`, `SectionHeader`) plus one new one (`AvatarStack`) into `lib/core/widgets/`. Then restyle each screen in place, reusing its existing data-fetch logic untouched except where a screen's current behavior is a stub that a new widget would otherwise render meaninglessly (Add Expense's payer/split-amount collection; Group Detail's raw-UUID names) — those two get just enough wiring to be real, nothing more.

**Tech Stack:** Flutter (Material 3), `flutter_riverpod`, `supabase_flutter`. No new dependencies.

## Global Constraints

- No new repository or RPC methods — every data call already exists in the codebase (`FriendRepository.getPublicProfiles`/`getMyProfile`, `GroupRepository`, `ExpenseRepository.createExpense`'s existing `percentages`/`exactAmounts` params, direct `client.rpc(...)`/`client.from(...)` calls already present in each screen).
- No new screens, no new Flutter packages, no changes to `supabase/migrations/`.
- `flutter test` must stay green after every task — in particular `test/features/home/home_screen_test.dart` (asserts literal `'Friends'`/`'Groups'` text) and `test/features/expenses/expense_detail_screen_test.dart` (asserts `'Edit'`, `'Delete'`, `'Coffee'`, `'Edited'`).
- Every screen keeps the app-wide `AppTheme.light` (cream background, coral accents) — no screen sets its own `Scaffold`/`AppBar` colors that fight it.
- Reference spec: `docs/superpowers/specs/2026-07-28-restyle-remaining-screens-design.md`.

---

### Task 1: Shared widget library

**Files:**
- Create: `lib/core/widgets/app_card.dart`
- Create: `lib/core/widgets/app_avatar.dart`
- Create: `lib/core/widgets/avatar_stack.dart`
- Create: `lib/core/widgets/balance_amount.dart`
- Create: `lib/core/widgets/balance_summary_card.dart`
- Create: `lib/core/widgets/empty_state_box.dart`
- Create: `lib/core/widgets/section_header.dart`
- Create: `lib/core/widgets/widgets.dart` (barrel export)

**Interfaces:**
- Produces (used by every later task):
  - `AppCard({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(14), VoidCallback? onTap})`
  - `AppAvatar({required String seed, String? label, IconData? icon, double size = 44})`
  - `AvatarStack({required List<String> seeds, required List<String> labels, double size = 36, double overlap = 20})`
  - `BalanceAmount({required double balance, TextStyle? style})`
  - `BalanceSummaryCard({required double balance, bool loading = false, String settledMessage = 'All settled up'})`
  - `EmptyStateBox({required IconData icon, required String message})`
  - `SectionHeader({required String title})`
  - Import all of the above via `import 'package:meowes_app/core/widgets/widgets.dart';`

- [ ] **Step 1: Write `AppCard`**

```dart
// lib/core/widgets/app_card.dart
import 'package:flutter/material.dart';

/// White rounded container — the base "row card" used for every
/// friend/group/expense/settlement list item across the app.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: card,
      ),
    );
  }
}
```

- [ ] **Step 2: Write `AppAvatar`**

```dart
// lib/core/widgets/app_avatar.dart
import 'package:flutter/material.dart';
import 'package:meowes_app/core/app_theme.dart';

/// Circular avatar with a deterministic color from [seed]. Shows the first
/// letter of [label] if given, otherwise [icon] (defaults to a person icon).
class AppAvatar extends StatelessWidget {
  final String seed;
  final String? label;
  final IconData? icon;
  final double size;

  const AppAvatar({
    super.key,
    required this.seed,
    this.label,
    this.icon,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.avatarFor(seed),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: label != null && label!.isNotEmpty
          ? Text(
              label![0].toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.4,
              ),
            )
          : Icon(icon ?? Icons.person, color: Colors.white, size: size * 0.5),
    );
  }
}
```

- [ ] **Step 3: Write `AvatarStack`**

```dart
// lib/core/widgets/avatar_stack.dart
import 'package:flutter/material.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/widgets/app_avatar.dart';

/// A row of overlapping [AppAvatar]s (each painted over the previous one),
/// for showing a group's members at a glance. [seeds] and [labels] must be
/// the same length and in the same order.
class AvatarStack extends StatelessWidget {
  final List<String> seeds;
  final List<String> labels;
  final double size;
  final double overlap;

  const AvatarStack({
    super.key,
    required this.seeds,
    required this.labels,
    this.size = 36,
    this.overlap = 20,
  }) : assert(seeds.length == labels.length);

  @override
  Widget build(BuildContext context) {
    if (seeds.isEmpty) return const SizedBox.shrink();
    final width = size + overlap * (seeds.length - 1);
    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < seeds.length; i++)
            Positioned(
              left: overlap * i,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.cream, width: 2),
                ),
                child: AppAvatar(seed: seeds[i], label: labels[i], size: size),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Write `BalanceAmount`**

```dart
// lib/core/widgets/balance_amount.dart
import 'package:flutter/material.dart';
import 'package:meowes_app/core/app_theme.dart';

/// Inline colored "+₹420.00" / "-₹150.00" / "Settled" text for a single
/// friend/group/settlement row. balance > 0 means money is owed TO the
/// signed-in user; balance < 0 means the signed-in user owes it.
class BalanceAmount extends StatelessWidget {
  final double balance;
  final TextStyle? style;

  const BalanceAmount({super.key, required this.balance, this.style});

  @override
  Widget build(BuildContext context) {
    final isOwed = balance > 0.005;
    final isOwing = balance < -0.005;
    final color = isOwed
        ? AppColors.owedText
        : (isOwing ? AppColors.owingText : AppColors.settledText);
    final text = isOwed
        ? '+₹${balance.toStringAsFixed(2)}'
        : (isOwing ? '-₹${balance.abs().toStringAsFixed(2)}' : 'Settled');
    return Text(
      text,
      style: (style ?? const TextStyle(fontWeight: FontWeight.w700)).copyWith(color: color),
    );
  }
}
```

- [ ] **Step 5: Write `BalanceSummaryCard`**

```dart
// lib/core/widgets/balance_summary_card.dart
import 'package:flutter/material.dart';
import 'package:meowes_app/core/app_theme.dart';

/// Full-width tinted card: "You are owed"/"You owe"/"All settled up" plus
/// the amount. Used for Home's overall summary and Friend Detail's balance.
class BalanceSummaryCard extends StatelessWidget {
  final double balance;
  final bool loading;
  final String settledMessage;

  const BalanceSummaryCard({
    super.key,
    required this.balance,
    this.loading = false,
    this.settledMessage = 'All settled up',
  });

  @override
  Widget build(BuildContext context) {
    final isOwed = balance > 0.005;
    final isOwing = balance < -0.005;
    final bg = isOwed ? AppColors.owedBg : (isOwing ? AppColors.owingBg : AppColors.settledBg);
    final fg = isOwed ? AppColors.owedText : (isOwing ? AppColors.owingText : AppColors.settledText);
    final label = isOwed ? 'You are owed' : (isOwing ? 'You owe' : settledMessage);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 6),
          if (loading)
            SizedBox(
              height: 30,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            )
          else if (!isOwed && !isOwing)
            const Text('🐾', style: TextStyle(fontSize: 26))
          else
            Text(
              '₹${balance.abs().toStringAsFixed(2)}',
              style: TextStyle(color: fg, fontSize: 30, fontWeight: FontWeight.w800),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Write `EmptyStateBox`**

```dart
// lib/core/widgets/empty_state_box.dart
import 'package:flutter/material.dart';
import 'package:meowes_app/core/app_theme.dart';

class EmptyStateBox extends StatelessWidget {
  final IconData icon;
  final String message;

  const EmptyStateBox({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(
          children: [
            Icon(icon, color: AppColors.textMuted, size: 28),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
          ],
        ),
      );
}
```

- [ ] **Step 7: Write `SectionHeader`**

```dart
// lib/core/widgets/section_header.dart
import 'package:flutter/material.dart';
import 'package:meowes_app/core/app_theme.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textDark),
      );
}
```

- [ ] **Step 8: Write the barrel export**

```dart
// lib/core/widgets/widgets.dart
export 'app_avatar.dart';
export 'app_card.dart';
export 'avatar_stack.dart';
export 'balance_amount.dart';
export 'balance_summary_card.dart';
export 'empty_state_box.dart';
export 'section_header.dart';
```

- [ ] **Step 9: Verify it compiles**

Run: `flutter analyze lib/core/widgets/`
Expected: `No issues found!`

- [ ] **Step 10: Commit**

```bash
git add lib/core/widgets/
git commit -m "Add shared AppCard/AppAvatar/AvatarStack/BalanceAmount/BalanceSummaryCard/EmptyStateBox/SectionHeader widgets"
```

---

### Task 2: Refactor Home screen onto shared widgets + wire tile navigation

**Files:**
- Modify: `lib/features/home/home_screen.dart` (full replacement)

**Interfaces:**
- Consumes: `AppCard`, `AppAvatar`, `BalanceAmount`, `BalanceSummaryCard`, `EmptyStateBox`, `SectionHeader` from Task 1; `FriendDetailScreen({required String friendUserId})` (unchanged constructor, from `lib/features/friends/friend_detail_screen.dart`); `GroupDetailScreen({required String groupId})` (unchanged constructor, from `lib/features/groups/group_detail_screen.dart`).
- Produces: no change to `HomeScreen`'s own public API (still `const HomeScreen()`).

- [ ] **Step 1: Replace `lib/features/home/home_screen.dart`**

```dart
// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/features/friends/friend_detail_screen.dart';
import 'package:meowes_app/features/groups/create_group_screen.dart';
import 'package:meowes_app/features/groups/group_detail_screen.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/friendship.dart';
import 'package:meowes_app/models/group.dart';
import 'package:meowes_app/repositories/friend_repository.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final friendRepo = ref.watch(friendRepositoryProvider);
    final groupRepo = ref.watch(groupRepositoryProvider);
    final me = client.auth.currentUser!.id;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            _GreetingHeader(friendRepo: friendRepo),
            const SizedBox(height: 20),
            StreamBuilder<List<Friendship>>(
              stream: friendRepo.watchFriendships(),
              builder: (context, snapshot) {
                final friendIds = (snapshot.data ?? [])
                    .where((f) => f.status == FriendshipStatus.accepted)
                    .map((f) => f.userIdA == me ? f.userIdB : f.userIdA)
                    .toList();
                return _FriendsAndSummary(
                  me: me,
                  friendIds: friendIds,
                  client: client,
                  friendRepo: friendRepo,
                );
              },
            ),
            const SizedBox(height: 28),
            const SectionHeader(title: 'Groups'),
            const SizedBox(height: 12),
            StreamBuilder<List<Group>>(
              stream: groupRepo.watchMyGroups(),
              builder: (context, snapshot) {
                final groups = snapshot.data ?? [];
                if (groups.isEmpty) {
                  return const EmptyStateBox(
                    icon: Icons.groups_2_outlined,
                    message: 'No groups yet — create one to split with a crew.',
                  );
                }
                return Column(
                  children: [
                    for (final g in groups) ...[
                      _GroupTile(group: g, me: me, client: client),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddMenu(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.settledBg,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_add_alt, color: AppColors.coral),
              title: const Text('Add a friend'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddFriendScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add, color: AppColors.coral),
              title: const Text('Create a group'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  final FriendRepository friendRepo;
  const _GreetingHeader({required this.friendRepo});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      future: friendRepo.getMyProfile(),
      builder: (context, snapshot) {
        final name = snapshot.data?.name;
        return Row(
          children: [
            Expanded(
              child: Text(
                name != null ? 'Hi $name! 👋' : 'Hi there! 👋',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: const Icon(Icons.notifications_none, color: AppColors.textDark),
            ),
          ],
        );
      },
    );
  }
}

class _FriendsData {
  final Map<String, AppUser> profiles;
  final Map<String, double> balances;
  const _FriendsData({required this.profiles, required this.balances});
}

class _FriendsAndSummary extends StatelessWidget {
  final String me;
  final List<String> friendIds;
  final SupabaseClient client;
  final FriendRepository friendRepo;

  const _FriendsAndSummary({
    required this.me,
    required this.friendIds,
    required this.client,
    required this.friendRepo,
  });

  Future<_FriendsData> _load() async {
    if (friendIds.isEmpty) {
      return const _FriendsData(profiles: {}, balances: {});
    }
    final profiles = await friendRepo.getPublicProfiles(friendIds);
    final balanceEntries = await Future.wait(friendIds.map((id) async {
      final b = await client.rpc('get_friend_balance', params: {'user_a': me, 'user_b': id});
      return MapEntry(id, (b as num?)?.toDouble() ?? 0.0);
    }));
    return _FriendsData(
      profiles: {for (final p in profiles) p.id: p},
      balances: Map.fromEntries(balanceEntries),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_FriendsData>(
      future: _load(),
      builder: (context, snapshot) {
        final data = snapshot.data ?? const _FriendsData(profiles: {}, balances: {});
        final total = data.balances.values.fold<double>(0, (a, b) => a + b);
        final loading = friendIds.isNotEmpty && snapshot.connectionState == ConnectionState.waiting;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BalanceSummaryCard(balance: total, loading: loading),
            const SizedBox(height: 24),
            const SectionHeader(title: 'Friends'),
            const SizedBox(height: 12),
            if (friendIds.isEmpty)
              const EmptyStateBox(
                icon: Icons.pets,
                message: 'No friends yet — add one to start splitting expenses.',
              )
            else
              Column(
                children: [
                  for (final id in friendIds) ...[
                    _FriendTile(
                      friendUserId: id,
                      name: data.profiles[id]?.name ?? '...',
                      balance: data.balances[id] ?? 0,
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
          ],
        );
      },
    );
  }
}

class _FriendTile extends StatelessWidget {
  final String friendUserId;
  final String name;
  final double balance;
  const _FriendTile({required this.friendUserId, required this.name, required this.balance});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => FriendDetailScreen(friendUserId: friendUserId)),
      ),
      child: Row(
        children: [
          AppAvatar(seed: friendUserId, label: name),
          const SizedBox(width: 12),
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
          BalanceAmount(balance: balance),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final Group group;
  final String me;
  final SupabaseClient client;
  const _GroupTile({required this.group, required this.me, required this.client});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: client.rpc('get_group_debts', params: {'target_group_id': group.id}),
      builder: (context, snapshot) {
        final debts = (snapshot.data as List<dynamic>?) ?? [];
        var net = 0.0;
        for (final d in debts) {
          final amount = double.tryParse(d['amount'].toString()) ?? 0;
          if (d['to_user'] == me) net += amount;
          if (d['from_user'] == me) net -= amount;
        }
        return AppCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: group.id)),
          ),
          child: Row(
            children: [
              AppAvatar(seed: group.id, icon: Icons.groups),
              const SizedBox(width: 12),
              Expanded(child: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
              BalanceAmount(balance: net),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 2: Run the Home widget test**

Run: `flutter test test/features/home/home_screen_test.dart`
Expected: `All tests passed!` (it still finds literal `'Friends'`/`'Groups'` text — `SectionHeader` renders the same string).

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/features/home/home_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/home/home_screen.dart
git commit -m "Refactor Home screen onto shared widgets, make friend/group tiles tappable"
```

---

### Task 3: Restyle Sign In screen

**Files:**
- Modify: `lib/features/auth/sign_in_screen.dart` (full replacement)

**Interfaces:**
- Consumes: `AppColors` from `lib/core/app_theme.dart`; `AuthRepository.signInWithGoogle()`, `.signInWithApple()`, `.signInWithTestAccount(String, String)` (all unchanged, from `lib/repositories/auth_repository.dart`).
- Produces: no change to `authRepositoryProvider`'s declaration site (stays in this file, as before, since `profile_setup_screen.dart` imports it from here).

- [ ] **Step 1: Replace `lib/features/auth/sign_in_screen.dart`**

```dart
// lib/features/auth/sign_in_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/repositories/auth_repository.dart';
import 'package:meowes_app/features/auth/profile_setup_screen.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authRepo = ref.watch(authRepositoryProvider);

    Future<void> handleSignIn(Future<void> Function() signIn) async {
      await signIn();
      if (context.mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
        );
      }
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🐱', style: TextStyle(fontSize: 96)),
              const SizedBox(height: 16),
              const Text(
                'Meowes',
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: AppColors.coral),
              ),
              const SizedBox(height: 8),
              const Text(
                'Split expenses. Stronger friendships.',
                style: TextStyle(fontSize: 15, color: AppColors.textMuted),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => handleSignIn(authRepo.signInWithGoogle),
                  child: const Text('Continue with Google'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => handleSignIn(authRepo.signInWithApple),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textDark,
                    side: const BorderSide(color: AppColors.textDark),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  child: const Text('Continue with Apple'),
                ),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 32),
                const Divider(color: AppColors.divider),
                const SizedBox(height: 8),
                const Text('Dev tools', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => handleSignIn(
                    () => authRepo.signInWithTestAccount('testuser1@meowes.dev', 'MeowesDevTest123!'),
                  ),
                  child: const Text('Sign in as Test User 1'),
                ),
                TextButton(
                  onPressed: () => handleSignIn(
                    () => authRepo.signInWithTestAccount('testuser2@meowes.dev', 'MeowesDevTest123!'),
                  ),
                  child: const Text('Sign in as Test User 2'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/features/auth/sign_in_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Run full test suite**

Run: `flutter test`
Expected: `All tests passed!` (no test targets this screen directly, but it's imported transitively by `root_screen.dart`, which nothing tests either — this just confirms the app still compiles clean).

- [ ] **Step 4: Commit**

```bash
git add lib/features/auth/sign_in_screen.dart
git commit -m "Restyle Sign In screen with cat/cream/coral theme"
```

---

### Task 4: Restyle Profile Setup screen

**Files:**
- Modify: `lib/features/auth/profile_setup_screen.dart` (full replacement)

**Interfaces:**
- Consumes: `AppColors` from `lib/core/app_theme.dart`; `authRepositoryProvider` from Task 3's `sign_in_screen.dart` (import unchanged); `AuthRepository.upsertProfile({required String name, String? avatarUrl, String? phoneNumber})` (unchanged).

- [ ] **Step 1: Replace `lib/features/auth/profile_setup_screen.dart`**

```dart
// lib/features/auth/profile_setup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/features/auth/sign_in_screen.dart';
import 'package:meowes_app/features/home/home_screen.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your profile')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(color: AppColors.owedBg, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Icon(Icons.pets, size: 40, color: AppColors.coral),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone number (optional, for friend search)',
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final authRepo = ref.read(authRepositoryProvider);
                  await authRepo.upsertProfile(
                    name: _nameController.text.trim(),
                    phoneNumber: _phoneController.text.trim().isEmpty
                        ? null
                        : _phoneController.text.trim(),
                  );
                  if (context.mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                    );
                  }
                },
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/features/auth/profile_setup_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Run full test suite**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/auth/profile_setup_screen.dart
git commit -m "Restyle Profile Setup screen"
```

---

### Task 5: Restyle Friend Detail screen

**Files:**
- Modify: `lib/features/friends/friend_detail_screen.dart` (full replacement)

**Interfaces:**
- Consumes: `BalanceSummaryCard` from Task 1; `AppColors` from `app_theme.dart`; `AddExpenseScreen({String? groupId, required List<String> participantIds})` (unchanged, from `lib/features/expenses/add_expense_screen.dart` — Task 9 changes its body but not this constructor); `SettleUpScreen({required String toUser, required int amountMinorUnits, String? groupId})` (unchanged, from `lib/features/settlements/settle_up_screen.dart`).

- [ ] **Step 1: Replace `lib/features/friends/friend_detail_screen.dart`**

```dart
// lib/features/friends/friend_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/expenses/add_expense_screen.dart';
import 'package:meowes_app/features/settlements/settle_up_screen.dart';

class FriendDetailScreen extends ConsumerWidget {
  final String friendUserId;
  const FriendDetailScreen({super.key, required this.friendUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final me = client.auth.currentUser!.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Friend')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: FutureBuilder(
          future: client.rpc('get_friend_balance', params: {
            'user_a': me,
            'user_b': friendUserId,
          }),
          builder: (context, snapshot) {
            final balance = (snapshot.data as num?)?.toDouble() ?? 0;
            // get_friend_balance(me, friend) is positive when the friend owes
            // me, negative when I owe the friend. Settling here means "I paid
            // this" (markPaid always records from_user = me), so the button
            // only makes sense when I'm the one who owes — offering it when
            // the friend owes me would record a payment in the wrong direction.
            final iOwe = balance < -0.005;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BalanceSummaryCard(balance: balance),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AddExpenseScreen(
                              participantIds: [me, friendUserId],
                            ),
                          ),
                        ),
                        child: const Text('Add Expense'),
                      ),
                    ),
                    if (iOwe) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SettleUpScreen(
                                toUser: friendUserId,
                                amountMinorUnits: (balance.abs() * 100).round(),
                              ),
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.coral,
                            side: const BorderSide(color: AppColors.coral),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                          ),
                          child: const Text('Settle Up'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/features/friends/friend_detail_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Run full test suite**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/friends/friend_detail_screen.dart
git commit -m "Restyle Friend Detail screen with BalanceSummaryCard"
```

---

### Task 6: Restyle Group Detail screen (with member name resolution)

**Files:**
- Modify: `lib/features/groups/group_detail_screen.dart` (full replacement)

**Interfaces:**
- Consumes: `AvatarStack`, `AppCard`, `EmptyStateBox`, `SectionHeader` from Task 1; `AppColors` from `app_theme.dart`; `friendRepositoryProvider` (from `lib/features/friends/add_friend_screen.dart`, exposing `FriendRepository.getPublicProfiles(List<String>) -> Future<List<AppUser>>`, unchanged); `SettleUpScreen` (unchanged, as in Task 5).

- [ ] **Step 1: Replace `lib/features/groups/group_detail_screen.dart`**

```dart
// lib/features/groups/group_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart' show friendRepositoryProvider;
import 'package:meowes_app/features/settlements/settle_up_screen.dart';
import 'package:meowes_app/models/app_user.dart';

class _GroupDetailData {
  final List<String> memberIds;
  final Map<String, String> namesById;
  final List<dynamic> debts;
  const _GroupDetailData({required this.memberIds, required this.namesById, required this.debts});
}

class GroupDetailScreen extends ConsumerWidget {
  final String groupId;
  const GroupDetailScreen({super.key, required this.groupId});

  Future<_GroupDetailData> _load(WidgetRef ref) async {
    final client = ref.read(supabaseClientProvider);
    final friendRepo = ref.read(friendRepositoryProvider);

    final memberRows = await client.from('group_members').select('user_id').eq('group_id', groupId);
    final memberIds = memberRows.map((r) => r['user_id'] as String).toList();

    final debtsRaw = await client.rpc('get_group_debts', params: {'target_group_id': groupId});
    final debts = (debtsRaw as List<dynamic>?) ?? [];

    final profiles = memberIds.isEmpty ? <AppUser>[] : await friendRepo.getPublicProfiles(memberIds);
    final namesById = {for (final p in profiles) p.id: p.name};

    return _GroupDetailData(memberIds: memberIds, namesById: namesById, debts: debts);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(supabaseClientProvider).auth.currentUser!.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Group')),
      body: FutureBuilder<_GroupDetailData>(
        future: _load(ref),
        builder: (context, snapshot) {
          final data = snapshot.data ?? const _GroupDetailData(memberIds: [], namesById: {}, debts: []);
          String nameOf(String id) => data.namesById[id] ?? 'Unknown';

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              AvatarStack(
                seeds: data.memberIds,
                labels: [for (final id in data.memberIds) nameOf(id)],
              ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Smart settle suggestions'),
              const SizedBox(height: 12),
              if (data.debts.isEmpty)
                const EmptyStateBox(
                  icon: Icons.celebration_outlined,
                  message: 'Everyone is settled up.',
                )
              else
                Column(
                  children: [
                    for (final d in data.debts) ...[
                      AppCard(
                        // markPaid always records from_user = me, so only the
                        // actual debtor's own row should be tappable into
                        // settle-up — otherwise a member could record a
                        // settlement in their own name for someone else's debt.
                        onTap: d['from_user'] == me
                            ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => SettleUpScreen(
                                      toUser: d['to_user'] as String,
                                      amountMinorUnits:
                                          (double.parse(d['amount'].toString()) * 100).round(),
                                      groupId: groupId,
                                    ),
                                  ),
                                )
                            : null,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${nameOf(d['from_user'] as String)} owes ${nameOf(d['to_user'] as String)}',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ),
                            Text(
                              '₹${d['amount']}',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.owingText),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/features/groups/group_detail_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Run full test suite**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/groups/group_detail_screen.dart
git commit -m "Restyle Group Detail screen; resolve member/debt names via getPublicProfiles"
```

---

### Task 7: Restyle Add Friend screen (recent-contacts avatar row)

**Files:**
- Modify: `lib/features/friends/add_friend_screen.dart` (full replacement)

**Interfaces:**
- Consumes: `AppCard`, `AppAvatar`, `SectionHeader` from Task 1; `AppColors` from `app_theme.dart`; `FriendRepository.watchFriendships()`, `.getPublicProfiles(List<String>)`, `.searchByPhone(String)`, `.sendFriendRequest(String)` (all unchanged).
- Produces: `friendRepositoryProvider` (unchanged declaration site — Task 6, Task 9, and Task 2 all import it from this file, as before).

- [ ] **Step 1: Replace `lib/features/friends/add_friend_screen.dart`**

```dart
// lib/features/friends/add_friend_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/friendship.dart';
import 'package:meowes_app/repositories/friend_repository.dart';

final friendRepositoryProvider = Provider<FriendRepository>(
  (ref) => FriendRepository(ref.watch(supabaseClientProvider)),
);

class AddFriendScreen extends ConsumerStatefulWidget {
  const AddFriendScreen({super.key});

  @override
  ConsumerState<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends ConsumerState<AddFriendScreen> {
  final _phoneController = TextEditingController();
  AppUser? _found;
  bool _searched = false;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(friendRepositoryProvider);
    final me = ref.watch(supabaseClientProvider).auth.currentUser!.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Add friend')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          StreamBuilder<List<Friendship>>(
            stream: repo.watchFriendships(),
            builder: (context, snapshot) {
              final friendIds = (snapshot.data ?? [])
                  .where((f) => f.status == FriendshipStatus.accepted)
                  .map((f) => f.userIdA == me ? f.userIdB : f.userIdA)
                  .toList();
              if (friendIds.isEmpty) return const SizedBox.shrink();
              return FutureBuilder<List<AppUser>>(
                future: repo.getPublicProfiles(friendIds),
                builder: (context, profileSnapshot) {
                  final profiles = profileSnapshot.data ?? [];
                  if (profiles.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'Recent'),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 76,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: profiles.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 16),
                          itemBuilder: (context, i) => Column(
                            children: [
                              AppAvatar(seed: profiles[i].id, label: profiles[i].name, size: 48),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: 56,
                                child: Text(
                                  profiles[i].name,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  );
                },
              );
            },
          ),
          const SectionHeader(title: 'Search by phone'),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            decoration: const InputDecoration(labelText: 'Phone number'),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final result = await repo.searchByPhone(_phoneController.text.trim());
                setState(() {
                  _found = result;
                  _searched = true;
                });
              },
              child: const Text('Search'),
            ),
          ),
          if (_searched && _found != null) ...[
            const SizedBox(height: 16),
            AppCard(
              child: Row(
                children: [
                  AppAvatar(seed: _found!.id, label: _found!.name),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_found!.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ElevatedButton(
                    onPressed: () async {
                      await repo.sendFriendRequest(_found!.id);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: const Text('Send request'),
                  ),
                ],
              ),
            ),
          ],
          if (_searched && _found == null) ...[
            const SizedBox(height: 16),
            const Text(
              'Not registered yet — share an invite link instead.',
              style: TextStyle(color: AppColors.textMuted),
            ),
            // Invite-link generation reuses the group invite_code mechanism
            // from Task 9 and is wired as a share-sheet action, not a new
            // backend concept.
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/features/friends/add_friend_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Run full test suite**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/friends/add_friend_screen.dart
git commit -m "Restyle Add Friend screen; add recent-contacts avatar row"
```

---

### Task 8: Restyle Create Group screen (invite-code state)

**Files:**
- Modify: `lib/features/groups/create_group_screen.dart` (full replacement)

**Interfaces:**
- Consumes: `AppCard`, `SectionHeader` from Task 1; `AppColors` from `app_theme.dart`; `GroupRepository.createGroup(String) -> Future<Group>` (unchanged); `Group.inviteCode` (existing field, from `lib/models/group.dart`).
- Produces: `groupRepositoryProvider` (unchanged declaration site — Task 2 imports it from here, as before).

- [ ] **Step 1: Replace `lib/features/groups/create_group_screen.dart`**

```dart
// lib/features/groups/create_group_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/models/group.dart';
import 'package:meowes_app/repositories/group_repository.dart';

final groupRepositoryProvider = Provider<GroupRepository>(
  (ref) => GroupRepository(ref.watch(supabaseClientProvider)),
);

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _nameController = TextEditingController();
  Group? _created;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(groupRepositoryProvider);

    if (_created != null) {
      final group = _created!;
      return Scaffold(
        appBar: AppBar(title: const Text('Group created')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(group.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Invite code'),
              const SizedBox(height: 12),
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.inviteCode,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 1.2),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: AppColors.coral),
                      onPressed: () => Clipboard.setData(ClipboardData(text: group.inviteCode)),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(group),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Create group')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Group name'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final group = await repo.createGroup(_nameController.text.trim());
                  setState(() => _created = group);
                },
                child: const Text('Create'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/features/groups/create_group_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Run full test suite**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/groups/create_group_screen.dart
git commit -m "Restyle Create Group screen; show invite code after creation"
```

---

### Task 9: Restyle Add Expense screen (split-type tiles, percentage fields, exact sliders)

**Files:**
- Modify: `lib/features/expenses/add_expense_screen.dart` (full replacement)

**Interfaces:**
- Consumes: `AppAvatar`, `SectionHeader` from Task 1; `AppColors` from `app_theme.dart`; `friendRepositoryProvider` (from Task 7's `add_friend_screen.dart`, `FriendRepository.getPublicProfiles`); `ExpenseRepository.createExpense({required String description, required int amountMinorUnits, String? groupId, required String paidBy, required SplitType splitType, required List<String> participantIds, Map<String, double>? percentages, Map<String, int>? exactAmounts, required DateTime expenseDate})` (unchanged signature — this task is the first caller to actually pass non-null `percentages`/`exactAmounts`); `SplitType` enum (`equal`, `percentage`, `exact`, unchanged, from `lib/splitting/split_calculator.dart`).
- Produces: no change to `AddExpenseScreen({String? groupId, required List<String> participantIds})`'s constructor — Task 5 and Task 10 both construct it exactly as before.

- [ ] **Step 1: Replace `lib/features/expenses/add_expense_screen.dart`**

```dart
// lib/features/expenses/add_expense_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart' show friendRepositoryProvider;
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/splitting/split_calculator.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  final String? groupId;
  final List<String> participantIds;

  const AddExpenseScreen({super.key, this.groupId, required this.participantIds});

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
    _paidBy = widget.participantIds.first;
    final evenPercent = (100 / widget.participantIds.length).toStringAsFixed(1);
    for (final id in widget.participantIds) {
      _percentControllers[id] = TextEditingController(text: evenPercent);
      _exactAmounts[id] = 0;
    }
    _amountController.addListener(_onAmountChanged);
    _profilesFuture = ref.read(friendRepositoryProvider).getPublicProfiles(widget.participantIds);
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
    if (_splitType == SplitType.percentage) return (_percentTotal - 100).abs() < 0.01;
    if (_splitType == SplitType.exact) return (_exactTotal - _totalAmount).abs() < 0.01;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(expenseRepositoryProvider);
    _me = ref.watch(supabaseClientProvider).auth.currentUser!.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Add expense')),
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
                          await repo.createExpense(
                            description: _descriptionController.text.trim(),
                            amountMinorUnits: amountMinorUnits,
                            groupId: widget.groupId,
                            paidBy: _paidBy,
                            splitType: _splitType,
                            participantIds: widget.participantIds,
                            percentages: _splitType == SplitType.percentage
                                ? {
                                    for (final id in widget.participantIds)
                                      id: double.parse(_percentControllers[id]!.text),
                                  }
                                : null,
                            exactAmounts: _splitType == SplitType.exact
                                ? {
                                    for (final id in widget.participantIds)
                                      id: (_exactAmounts[id]! * 100).round(),
                                  }
                                : null,
                            expenseDate: DateTime.now(),
                          );
                          if (context.mounted) Navigator.of(context).pop();
                        }
                      : null,
                  child: const Text('Save Expense'),
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
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/features/expenses/add_expense_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Run full test suite**

Run: `flutter test`
Expected: `All tests passed!` (in particular `test/repositories/expense_repository_test.dart`, which tests `ExpenseRepository` directly and is unaffected by this screen-only change).

- [ ] **Step 4: Commit**

```bash
git add lib/features/expenses/add_expense_screen.dart
git commit -m "Restyle Add Expense screen; wire paid-by, percentage, and exact-split inputs"
```

---

### Task 10: Restyle Expense Detail screen

**Files:**
- Modify: `lib/features/expenses/expense_detail_screen.dart` (full replacement)

**Interfaces:**
- Consumes: `AppColors` from `app_theme.dart`; `AddExpenseScreen({String? groupId, required List<String> participantIds})` from Task 9 (constructor unchanged); `ExpenseRepository.deleteExpense(String)` (unchanged); `Expense.isEdited`, `.description`, `.amountMinorUnits`, `.groupId`, `.id` (unchanged, from `lib/models/expense.dart`).

- [ ] **Step 1: Replace `lib/features/expenses/expense_detail_screen.dart`**

```dart
// lib/features/expenses/expense_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/features/expenses/add_expense_screen.dart';

class ExpenseDetailScreen extends ConsumerWidget {
  final Expense expense;
  const ExpenseDetailScreen({super.key, required this.expense});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(expenseRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(expense.description)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '₹${(expense.amountMinorUnits / 100).toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            if (expense.isEdited)
              const Text('Edited', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AddExpenseScreen(
                          groupId: expense.groupId,
                          participantIds: const [], // populated from expense_splits when wired to a live expense
                        ),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.coral,
                      side: const BorderSide(color: AppColors.coral),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    child: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await repo.deleteExpense(expense.id);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.owingText,
                      side: const BorderSide(color: AppColors.owingText),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    child: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run the Expense Detail widget test**

Run: `flutter test test/features/expenses/expense_detail_screen_test.dart`
Expected: `All tests passed!` (still finds `'Edit'`, `'Delete'`, `'Coffee'` in test 1 and `'Edited'` in test 2).

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/features/expenses/expense_detail_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/expenses/expense_detail_screen.dart
git commit -m "Restyle Expense Detail screen"
```

---

### Task 11: Restyle Settle Up screen

**Files:**
- Modify: `lib/features/settlements/settle_up_screen.dart` (full replacement)

**Interfaces:**
- Consumes: `AppColors` from `app_theme.dart`; `SettlementRepository.markPaid({required String toUser, required int amountMinorUnits, String? groupId})` (unchanged).
- Produces: `settlementRepositoryProvider`, `SettleUpScreen({required String toUser, required int amountMinorUnits, String? groupId})` (both unchanged — consumed by Task 5 and Task 6).

- [ ] **Step 1: Replace `lib/features/settlements/settle_up_screen.dart`**

```dart
// lib/features/settlements/settle_up_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/repositories/settlement_repository.dart';

final settlementRepositoryProvider = Provider<SettlementRepository>(
  (ref) => SettlementRepository(ref.watch(supabaseClientProvider)),
);

class SettleUpScreen extends ConsumerWidget {
  final String toUser;
  final int amountMinorUnits;
  final String? groupId;

  const SettleUpScreen({
    super.key,
    required this.toUser,
    required this.amountMinorUnits,
    this.groupId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(settlementRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settle up')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🐾', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 16),
              Text(
                '₹${(amountMinorUnits / 100).toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: AppColors.owingText),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await repo.markPaid(
                      toUser: toUser,
                      amountMinorUnits: amountMinorUnits,
                      groupId: groupId,
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('Mark as Paid'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/features/settlements/settle_up_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Run full test suite**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/settlements/settle_up_screen.dart
git commit -m "Restyle Settle Up screen"
```

---

### Task 12: Final verification

**Files:** none (verification only).

**Interfaces:** none.

- [ ] **Step 1: Full analyzer pass**

Run: `flutter analyze`
Expected: only the pre-existing `anonKey` deprecation info in `lib/main.dart` (unrelated to this plan) — no new issues.

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: `All tests passed!` (21+ tests, matching the count from before this plan).

- [ ] **Step 3: Emulator spot-check — Friend Detail**

With the Android emulator running the app (per the earlier Home-screen session: `flutter run -d emulator-5554 --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`, signed in as the `testuser1`/"Alex" dev account), tap a friend tile on Home (e.g. "Priya", seeded with balance -1700). Confirm:
- Navigates to the restyled Friend Detail screen.
- `BalanceSummaryCard` shows "You owe ₹1700.00" in red.
- Both "Add Expense" and "Settle Up" buttons are visible (since Alex owes Priya).

- [ ] **Step 4: Emulator spot-check — Group Detail**

From Home, tap the "Flatmates" group tile (seeded with net +200 for Alex). Confirm:
- Navigates to the restyled Group Detail screen.
- Avatar stack shows 3 members (Alex, Sam, John) — not raw UUID initials.
- "Smart settle suggestions" shows real names, e.g. "John owes Sam ₹500.00" and "John owes Alex ₹200.00", not UUIDs.

- [ ] **Step 5: Commit any fixes found during spot-check**

If steps 3–4 surface a bug, fix it, re-run `flutter analyze` and `flutter test`, then commit with a message describing the specific fix (not a generic "fix bug").
