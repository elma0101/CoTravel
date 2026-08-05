# CoTravel v0 roadmap

This is the adjusted roadmap followed by the repository. It preserves the
original product plan while reflecting that itinerary creation and discovery
were delivered together in milestone 3.

| Milestone | Scope | Status |
| --- | --- | --- |
| 0 | Development baseline: repository, CI, local mobile toolchains, environments | Complete |
| 1 | Application architecture: routing, Riverpod, configuration, shared async states | Complete |
| 2 | Authentication and trust: email onboarding, profile, avatar, LinkedIn status | Complete in preview; backend migration prepared |
| 3 | Itinerary and discovery: creation, ordered stops, capacity, costs, feed, filters, details | Complete |
| 4 | Mutual approval: traveler request, host decision, traveler confirmation, seat locking | Complete |
| 5 | Group coordination: confirmed-member conversation, realtime-style messages, unread state | Complete |
| 6 | Costs and logistics: live cost splits, host shortlist, external booking links | Complete |
| 7 | Safety and release hardening: report/block, moderation, authorization audit, analytics, accessibility and integration checks | Complete |
| 8 | Controlled beta: Supabase staging activation, TestFlight/Play testing, seed data, feedback and KPI dashboard | Implementation complete; external activation pending |
| 9 | PoC evidence and expansion readiness: timed usability evidence, service-only validation gate, immutable review snapshots | Implementation complete; real beta evidence pending |

## V0 boundaries

Included: verified profiles, trip creation and discovery, mutual approval,
private group messaging, dynamic cost estimates, external booking links,
reporting, blocking, manual moderation, and KPI analytics.

Excluded: in-app payments, direct booking, algorithmic matching,
government-ID verification, public social feeds, reputation scoring, and
multi-currency settlement.

## Milestone 8 entry criteria

- Apply all migrations to an isolated staging project.
- Complete the authorization scenarios in `security-audit.md` with two or more
  real test accounts.
- Configure LinkedIn OIDC and mobile callback URLs.
- Install a complete local Xcode/CocoaPods toolchain or validate the unsigned
  iOS build in CI.
- Prepare at least 15 representative seed itineraries without real personal
  data.

The implementation package is now ready: account-linked feedback, the
service-only KPI view, guarded fictional staging seed data, QA build artifacts,
and the operator checklist are in place. The external services listed above
remain activation requirements; see `controlled-beta-runbook.md`.

## Milestone 9 exit criteria

- Collect at least five real itinerary-creation timing samples and satisfy the
  documented evidence guardrail.
- Achieve the four specification KPIs with an adequate feedback sample.
- Observe real request, confirmation, and private-conversation activity.
- Pass the automated suite and manual security audit for the candidate build.
- Resolve all high-severity release blockers.
- Capture an immutable PoC review snapshot as described in
  `poc-validation-gate.md`.

The evidence tooling is complete. The exit criteria cannot be marked complete
until milestone 8 is activated and the controlled beta produces real data.
