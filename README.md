# CoTravel mobile app

Flutter foundation for the CoTravel peer-to-peer travel platform. The initial
scaffold targets Android and iOS and follows the approved warm, restrained
visual direction.

The project is pinned to Flutter 3.44.8 and Dart 3.12.2.

## Included

- Material 3 theme with reusable color, type, spacing, form, button, and
  navigation tokens
- Feature-first folders for Explore, Trips, Messages, and Profile
- Four-destination mobile shell with preserved tab state
- Starter Explore experience and intentional empty states
- Widget smoke tests for app startup and primary navigation
- Environment-aware Supabase bootstrap with a safe development preview mode
- Riverpod state ownership and guarded `go_router` navigation
- GitHub Actions checks for formatting, analysis, tests, Android, and iOS builds
- Passwordless email authentication and guarded profile onboarding
- Avatar upload, travel preferences, and LinkedIn identity-linking support
- Versioned Supabase schema with profile and storage Row Level Security
- Multi-stop itinerary creation with dates, capacity, and shared-cost estimates
- Interactive MapLibre route explorer with numbered stops, itinerary-map
  selection, route overview, and guided previous/next navigation
- Searchable trip discovery with date, travel-style, and host-trust filters
- My Trips catalog and detailed route, budget, and host views
- Profile-aware join requests with host approval and traveler reconfirmation
- Host candidate inbox and traveler-facing request status tracking
- Automatically created, member-only trip conversations after dual approval
- Group chat inbox with realtime unread badges, paginated history, optimistic
  delivery, safe retry, and system events
- Traveler action sheets on trip hosts and chat senders, with shared public
  profiles and confirmation-gated handoff into the relevant trip chat
- Live lodging and transport splits for any group size from one to capacity
- Confirmed-member booking shortlists with external provider handoff
- Host-managed cost estimates, booking links, and planning notes
- User reporting, immediate blocking, and a service-only moderation queue
- Block-aware trip discovery and concealed blocked-sender messages
- Privacy-minimized KPI event capture for the controlled beta
- Account-linked controlled-beta feedback with a safe-and-informed measure
- Service-only beta KPI dashboard and guarded 15-itinerary staging seed
- CI-retained Android QA, iOS inspection, and coverage artifacts
- Server-timestamped itinerary usability evidence for the three-minute PoC check
- Service-only PoC evidence gate and append-only stakeholder review snapshots

## Project structure

```text
lib/
├── app/                  # Application shell and global theme
├── core/widgets/         # Shared presentation components
└── features/             # Product features and their UI
```

## Run locally

Make sure Flutter is on your shell path. With the SDK location used during
project setup:

```bash
export PATH="$HOME/Developer/flutter/bin:$PATH"
```

```bash
flutter pub get
flutter run --dart-define-from-file=config/dev.json
```

Copy `config/dev.example.json` to `config/dev.json` first. Local configuration
files are ignored by Git. The default development configuration also works
without a backend and opens on an explicit preview sign-in screen.

`MAP_STYLE_URL` selects the MapLibre-compatible basemap. The example files use
CARTO's public Positron style, so route tiles require an internet connection.
The app's route and stop metadata remain independent of the basemap provider.

For staging, copy `config/staging.example.json` to `config/staging.json` and
replace the placeholders. Preview authentication is never enabled outside the
development environment.

## Quality checks

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Supabase restores existing sessions when configured, while local development
can use the clearly labelled preview session. Backend activation steps are in
`docs/supabase-setup.md`.

Preview mode includes five realistic trip listings. Trips created during a
preview session appear immediately in Explore and My Trips, which allows the
complete milestone 3 flow to be evaluated before Supabase is connected.
Preview mode also seeds both sides of milestone 4: one candidate for a hosted
trip and one host-approved invitation awaiting traveler confirmation.
It includes a confirmed Dades trip conversation so milestone 5 messaging can
be evaluated without external services.
All preview itineraries include map-ready route metadata, and familiar Morocco
city names retain a local coordinate fallback for older text-only trip records.
The same confirmed trip includes a shared-cost calculator and external booking
shortlist for milestone 6. The preview-owned Rif trip demonstrates the
host-only logistics editor.
Milestone 7 adds report/block preview flows from trip details and a Safety
Center under Profile. The adjusted roadmap is documented in
`docs/v0-roadmap.md`.
Milestone 8 adds a focused feedback flow under Profile and the staging beta
package documented in `docs/controlled-beta-runbook.md`. Store distribution is
intentionally pending private signing credentials and staging activation.
Milestone 9 adds the validation gate documented in
`docs/poc-validation-gate.md`; it remains evidence-pending until the controlled
beta runs with real participants.

## Local platform setup

Android API 36, build-tools 36.0.0, NDK 28.2, and CMake 3.22.1 were installed
during the initial setup. The remaining Android license audit must be completed
interactively by the developer:

```bash
flutter doctor --android-licenses
```

iOS builds require the full Xcode application and CocoaPods. CI runs the
unsigned iOS build independently on a macOS runner, but local iOS work should
begin only after `flutter doctor` reports a complete Xcode toolchain.
