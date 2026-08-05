# Supabase setup for CoTravel

Milestones 2 through 7 are designed to run in development preview without a
backend. Real email authentication, profile persistence, avatar uploads,
LinkedIn verification, and itinerary persistence become active after a
Supabase project is connected.

## 1. Create the projects

Create separate Supabase projects for staging and production. Do not reuse the
production database for local or staging testing.

Apply every SQL file in `supabase/migrations/` in filename order. The first
migration creates:

- public travel profiles with Row Level Security
- atomic profile completion and LinkedIn verification functions
- the public avatar bucket with owner-only write policies
- automatic profile rows for newly authenticated users

The second migration creates:

- published trips and ordered itinerary stops with Row Level Security
- indexed discovery fields for upcoming destinations
- an atomic `create_trip` function that validates the complete itinerary
- server-side enforcement that only onboarded, LinkedIn-verified hosts publish

The third migration creates:

- traveler join requests readable only by the traveler and relevant trip host
- explicit host approve/decline and traveler confirm/withdraw functions
- transactionally locked seat allocation after both sides approve
- active-request uniqueness to prevent duplicate or double-confirmed seats

The fourth migration creates:

- one private conversation per trip after the first confirmed traveler
- conversation membership for the host and confirmed travelers only
- member-gated message reads and writes with Row Level Security
- realtime message publication, unread tracking, and safe message RPCs

The fifth migration creates:

- private trip logistics readable only by hosts and confirmed travelers
- host-only updates for lodging and transport totals
- validated HTTP/HTTPS booking links and optional group planning notes
- a single atomic function for synchronizing the cost estimate and shortlist

The sixth migration creates:

- user blocks with bidirectional profile/trip discovery enforcement
- traveler safety reports and a service-role-only manual moderation queue
- prevention of new join requests between blocked accounts
- privacy-minimized, whitelisted analytics events with no client read access

The chat completion migration adds:

- member-gated cursor pagination instead of loading an entire conversation
- idempotent client message identifiers so a retry cannot duplicate a message
- server-returned delivery records for optimistic sending and visible retries
- monotonic, message-aware read positions for accurate unread counts

## 2. Configure authentication

In Authentication settings:

1. Enable email authentication and keep email confirmation enabled.
2. Add `com.cotravel.app://login-callback` to the redirect allow list.
3. Customize the email template as a magic-link message.
4. Enable manual identity linking.

For LinkedIn, create a LinkedIn application with the `Sign In with LinkedIn
using OpenID Connect` product. Enable LinkedIn (OIDC) in Supabase and configure
the client ID and secret. The callback URL shown by Supabase belongs in the
LinkedIn application settings.

## 3. Configure the Flutter app

Copy `config/staging.example.json` to `config/staging.json` and replace:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

Use only the publishable client key in the mobile app. Never add a Supabase
secret or service-role key to a JSON file, Dart source, or CI configuration.

Run the staging app with:

```bash
flutter run --dart-define-from-file=config/staging.json
```

## 4. Verify the integration

1. Request a sign-in link from a physical device or simulator.
2. Open the link and confirm the app routes to profile onboarding.
3. Complete the profile and upload an avatar.
4. Connect LinkedIn and use the refresh button after returning to the app.
5. Confirm that another authenticated account can read the completed profile
   but cannot update it or overwrite its avatar.
6. Publish a trip with at least two route stops and confirm it appears in My
   Trips and another account's Explore feed.
7. Confirm an unverified account cannot bypass the client and call
   `create_trip` directly.
8. Send a join request from a second verified account and verify the host can
   read the traveler profile and introduction.
9. Approve as the host and confirm that the participant count does not change
   until the traveler explicitly confirms.
10. Confirm as the traveler and verify exactly one seat is allocated even when
    the confirmation action is retried.
11. Verify a trip conversation appears automatically after confirmation and
    contains the host and confirmed traveler.
12. Confirm an authenticated non-member cannot select messages, subscribe to
    realtime message changes, call `send_chat_message`, or mark the chat read.
13. Send messages from two confirmed accounts and verify the inbox preview and
    unread count and bottom-navigation badge update correctly.
14. Disable the network while sending, verify the failed message remains in the
    conversation, reconnect, tap retry, and confirm only one copy is stored.
15. Add more than 40 messages, reopen the conversation, scroll upward, and
    confirm older pages load without a jump or duplicate messages.
16. Verify an unconfirmed traveler cannot select a trip's logistics row.
17. As the host, update both shared-cost totals and structured booking links.
18. Confirm a group member can read the links but cannot call
    `save_trip_logistics`, and that the per-person estimate changes with the
    confirmed participant count.
19. Block a host and verify both accounts lose profile/trip discovery access
    and cannot create a new join request through the RPC.
20. Submit a report and verify the reporter sees its public status but cannot
    read or change moderator notes.
21. Confirm an unrelated account cannot select blocks, reports, the moderation
    queue, or analytics rows.
22. Verify each analytics event is attributed to `auth.uid()` and unknown or
    oversized payloads are rejected.

Use `docs/security-audit.md` for the complete multi-account authorization
matrix and `docs/moderation-runbook.md` for the manual review procedure.

LinkedIn linking requires provider approval and real credentials, so preview
mode intentionally displays an already-completed test profile instead of
pretending to validate the external OAuth flow.
