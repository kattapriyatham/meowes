# Todo

- **Bottom dock missing right after signup** — `ProfileSetupScreen` navigates
  to the bare `HomeScreen` after account creation, not `HomeShell`, so the
  dock (Home/Pet/Friends/Groups/Activity/Profile) is absent until the next
  cold app launch, at which point `RootScreen` correctly routes to
  `HomeShell` since a `users` row now exists. Fix: have `ProfileSetupScreen`
  navigate to `HomeShell` instead of `HomeScreen` (`lib/features/root/root_screen.dart`,
  `lib/features/auth/profile_setup_screen.dart`).
