import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Web OAuth client ID from Google Cloud Console (not secret — client IDs
/// are public identifiers, only the web client's secret needs to stay out
/// of the repo, and that lives in Supabase's env-substituted auth config,
/// not here). Required as `serverClientId` on Android so the ID token
/// GoogleSignIn returns is audienced to this client rather than the
/// platform-specific Android one — Supabase's Google provider is
/// configured to accept this web client ID (see
/// supabase/config.toml's [auth.external.google]), not the Android one.
const _googleWebClientId =
    '470887959516-f2pklra4penbmv8bl931rk9rl6g1d6v2.apps.googleusercontent.com';

class AuthRepository {
  final SupabaseClient _client;
  AuthRepository(this._client);

  User? get currentUser => _client.auth.currentUser;

  Future<void> signInWithGoogle() async {
    final googleSignIn = GoogleSignIn(
      scopes: ['email'],
      serverClientId: _googleWebClientId,
    );
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

  /// Dev-only bypass for testing without native Google/Apple OAuth
  /// configuration: signs in with a pre-seeded email/password test account
  /// rather than a real provider. Only ever called from behind a
  /// kDebugMode guard in the UI.
  Future<void> signInWithTestAccount(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
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
