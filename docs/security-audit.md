# CoTravel v0 authorization audit

This matrix documents the intended database boundary after all migrations are
applied in filename order. Client-side visibility is usability only; Supabase
Row Level Security and security-definer RPC validation are authoritative.

| Resource | Read boundary | Mutation boundary | Automated control |
| --- | --- | --- | --- |
| Profiles | Authenticated users can read completed profiles unless either account blocked the other; users always see themselves | Owner only | Profile RLS policies |
| Trips and stops | Published trips are discoverable unless either account blocked the host; hosts see their own trips | Verified, onboarded host through `create_trip` | Trip/stops RLS and validated RPC |
| Join requests | Requesting traveler and relevant host only | Explicit state RPCs; confirmation locks the trip row before taking a seat | Request RLS, uniqueness index, transaction locks, block trigger |
| Conversations | Confirmed conversation members only | Members through validated message/read RPCs | Membership helper, RLS, confirmation trigger |
| Logistics | Trip host and confirmed travelers only; a host/traveler block removes traveler access | Host through `save_trip_logistics` | Membership helper and RLS |
| Blocks | Returned only to the blocking user through `my_blocked_users` | Blocking user through block/unblock RPCs | No direct authenticated table grants |
| Safety reports | Reporter sees a redacted status view; moderator notes are never returned | Reporter creates through RPC; service role reviews | No direct authenticated table grants; service-only queue |
| Analytics | No client read access | Authenticated actor through a whitelisted, size-limited RPC | No authenticated table grants |
| Avatars | Public image objects for the PoC; profile paths are disclosed only by profile access rules | Owner folder only | Storage policies and file limits |

## Abuse-case checks

Run these with separate host, traveler, unrelated, and blocked accounts:

1. An unrelated account cannot select private requests, conversations,
   messages, logistics, reports, blocks, or analytics rows.
2. A modified client cannot confirm a request owned by another traveler or
   approve one for another host.
3. Concurrent confirmation attempts cannot exceed trip capacity.
4. A blocked pair cannot read each other's profiles/trips or create a new join
   request, including by calling `create_join_request` directly.
5. A confirmed traveler cannot change cost totals or booking links.
6. Reporters cannot read or change moderator notes and report status.
7. Analytics rejects unknown event names, non-object properties, oversized
   metadata, and actor impersonation.
8. The block helper returns no relationship information for account pairs that
   do not include the caller.

## Accepted v0 limitations

- Avatar objects remain public for simple mobile rendering. Do not treat an
  avatar as sensitive data; move the bucket to signed URLs before broader
  public rollout.
- Blocking does not delete a confirmed group conversation. The client hides
  messages from blocked senders so evidence remains available to moderation.
- Government ID verification and automated risk scoring are outside v0.
- Security-definer functions require migration-owner protection and must never
  be editable by authenticated roles.
