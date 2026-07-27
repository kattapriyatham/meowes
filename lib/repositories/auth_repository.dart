import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthRepository {
  final SupabaseClient _client;
  AuthRepository(this._client);

  User? get currentUser => _client.auth.currentUser;

  Future<void> signInWithGoogle() async {
    final googleSignIn = GoogleSignIn(scopes: ['email']);
    final googleUser = await googleSignIn.signIn();
    final googleAuth = await googleUser!.authentication;
    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: googleAuth.idToken!,
      accessToken: googleAuth.accessToken,
    );
  }

  Future<void> signInWithApple() async {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: credential.identityToken!,
    );
  }

  Future<void> upsertProfile({
    required String name,
    String? avatarUrl,
    String? phoneNumber,
  }) async {
    final userId = currentUser!.id;
    await _client.from('users').upsert({
      'id': userId,
      'name': name,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (phoneNumber != null) 'phone_number': phoneNumber,
    });
  }
}
