# meowes_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Running against cloud Supabase

`lib/main.dart` reads `SUPABASE_URL`/`SUPABASE_ANON_KEY` from `--dart-define`
at build time — running `flutter run` bare will fail auth calls with
"No host specified in URI".

Use `scripts/run_dev.sh` instead: it fetches the anon key for the linked
cloud project (`supabase/.temp/project-ref`, set via `supabase link`) fresh
from the Supabase API each time, so no key is stored in the repo.

```sh
scripts/run_dev.sh              # picks a device interactively
scripts/run_dev.sh emulator-5554
```

Requires the `supabase` CLI (logged in, project linked) and `jq`.
