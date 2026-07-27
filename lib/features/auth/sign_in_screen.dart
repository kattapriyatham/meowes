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
