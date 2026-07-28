import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/features/auth/profile_setup_screen.dart';
import 'package:meowes_app/features/auth/sign_in_screen.dart';
import 'package:meowes_app/features/root/home_shell.dart';

/// Decides where a launch of the app lands: signed out goes to sign-in;
/// signed in but no `users` row yet goes to profile setup; otherwise home.
/// Runs once at app start — after that, each screen navigates forward
/// explicitly (SignInScreen -> ProfileSetupScreen -> HomeScreen).
class RootScreen extends ConsumerWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final user = client.auth.currentUser;
    if (user == null) {
      return const SignInScreen();
    }
    return FutureBuilder(
      future: client.from('users').select().eq('id', user.id).maybeSingle(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data == null
            ? const ProfileSetupScreen()
            : const HomeShell();
      },
    );
  }
}
