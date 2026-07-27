import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () async {
                await authRepo.signInWithGoogle();
                if (context.mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
                  );
                }
              },
              child: const Text('Continue with Google'),
            ),
            ElevatedButton(
              onPressed: () async {
                await authRepo.signInWithApple();
                if (context.mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
                  );
                }
              },
              child: const Text('Continue with Apple'),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 32),
              const Text('DEV ONLY', style: TextStyle(color: Colors.red)),
              ElevatedButton(
                onPressed: () async {
                  await authRepo.signInWithTestAccount(
                    'testuser1@meowes.dev',
                    'MeowesDevTest123!',
                  );
                  if (context.mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
                    );
                  }
                },
                child: const Text('Sign in as Test User 1'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await authRepo.signInWithTestAccount(
                    'testuser2@meowes.dev',
                    'MeowesDevTest123!',
                  );
                  if (context.mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
                    );
                  }
                },
                child: const Text('Sign in as Test User 2'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
