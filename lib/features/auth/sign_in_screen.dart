// lib/features/auth/sign_in_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
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
    final t = Theme.of(context).extension<GlassTokens>()!;

    Future<void> handleSignIn(Future<void> Function() signIn) async {
      await signIn();
      if (context.mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
        );
      }
    }

    return GlassScaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Meowes',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Split expenses. Stronger friendships.',
                style: TextStyle(fontSize: 15, color: t.textMuted),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: PillButton(
                  label: 'Continue with Google',
                  primary: true,
                  onTap: () => handleSignIn(authRepo.signInWithGoogle),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: PillButton(
                  label: 'Continue with Apple',
                  primary: false,
                  onTap: () => handleSignIn(authRepo.signInWithApple),
                ),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 32),
                Divider(color: t.textMuted.withValues(alpha: 0.2)),
                const SizedBox(height: 8),
                Text('Dev tools', style: TextStyle(color: t.textMuted, fontSize: 12)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => handleSignIn(
                    () => authRepo.signInWithTestAccount('testuser1@meowes.dev', 'MeowesDevTest123!'),
                  ),
                  child: Text(
                    'Sign in as Test User 1',
                    style: TextStyle(color: t.textSecondary),
                  ),
                ),
                TextButton(
                  onPressed: () => handleSignIn(
                    () => authRepo.signInWithTestAccount('testuser2@meowes.dev', 'MeowesDevTest123!'),
                  ),
                  child: Text(
                    'Sign in as Test User 2',
                    style: TextStyle(color: t.textSecondary),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
