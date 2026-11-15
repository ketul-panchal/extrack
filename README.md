# Spent

A private, offline expense tracker built with Flutter. No account, no cloud:
everything lives in a local SQLite database on the phone.

## Features

- **Fast entry**: calculator keypad (+ − × ÷), note autocomplete that remembers
  each note's category and amount, usage-ordered categories, Today/Yesterday dates
- **Expenses, income and transfers** across accounts (cash, bank, cards, wallets)
- **Budgets**: monthly overall and per-category limits, safe-to-spend per day,
  pace marker, month-end projection, alerts at 80% and 100%; the month can
  start on payday (e.g. the 25th)
- **Recurring payments**: auto-recorded when due (catches up after days offline)
  or confirmed with Pay/Skip
- **Savings goals** with deadlines and the monthly saving needed
- **Insights**: spending bars, pace vs last period, category donut, highlights
- **Activity** list and heat-map calendar, search with filters, swipe to delete with undo
- **Privacy**: PIN + Face ID/fingerprint app lock, hide-amounts mode, no INTERNET
  permission in release, excluded from Android cloud backup
- **Your data**: JSON backup/restore and CSV export to a file you choose
- Local reminders (daily nudge, bills due), light/dark themes, 7 accent colors,
  40 currencies, Western/Indian/European number formats

## Develop

Flutter 3.44 / Dart 3.12 (`/Users/brainbean/Documents/sdk/flutter`).

```sh
flutter pub get
dart run build_runner build      # after changing lib/core/database/database.dart
flutter analyze
flutter test                     # unit, database and app smoke tests
flutter run
```

## Build

```sh
flutter build apk --release                  # build/app/outputs/flutter-apk/app-release.apk
flutter build apk --release --split-per-abi  # smaller per-device APKs
```

Release builds are signed with the debug key; add your own keystore in
`android/app/build.gradle.kts` before publishing.

## App icon

The icon is rendered from the same painter the app uses
(`lib/shared/widgets/brand_logo.dart`):

```sh
RENDER_ICONS=1 flutter test test/tool/render_icons_test.dart
dart run flutter_launcher_icons
```

## Layout

```
lib/
  app/        router, shell (floating nav bar), root app
  core/       database (Drift), money, time, theme, settings, services
  data/       repositories and Riverpod providers
  domain/     analytics (pure Dart)
  features/   home, activity, transactions, plan, insights, accounts,
              categories, settings, lock, onboarding
  shared/     reusable widgets and motion
```
