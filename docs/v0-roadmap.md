# CoTravel v0 roadmap

This is the adjusted roadmap followed by the repository. The source documents
are the functional specification and UI mockups, which are kept outside this
public repository. Itinerary creation and discovery were delivered together in
milestone 3.

The milestones below were built and tested against preview mode. "Implemented"
does not mean the milestone meets the specification; see the completion plan.

| Milestone | Scope | Status |
| --- | --- | --- |
| 0 | Development baseline: repository, CI, local mobile toolchains, environments | Complete |
| 1 | Application architecture: routing, Riverpod, configuration, shared async states | Complete |
| 2 | Authentication and trust: email onboarding, profile, avatar, LinkedIn status | Implemented; not yet verified on a live backend |
| 3 | Itinerary and discovery: creation, ordered stops, capacity, costs, feed, filters, details | Implemented; no map view or host tags |
| 4 | Mutual approval: traveler request, host decision, traveler confirmation, seat locking | Implemented; backend confirmation fixed after database tests exposed a failure |
| 5 | Group coordination: confirmed-member conversation, realtime messages, paginated history, resilient delivery, unread state | Implemented; backend send fixed after database tests exposed a failure |
| 6 | Costs and logistics: live cost splits, host shortlist, external booking links | Implemented; links are entered by hand |
| 7 | Safety and release hardening: report/block, moderation, authorization audit, analytics | Implemented; manual audit not yet run; no integration or accessibility test suite |
| 8 | Controlled beta: Supabase staging activation, TestFlight/Play testing, seed data, feedback and KPI dashboard | Implementation complete; external activation pending |
| 9 | PoC evidence and expansion readiness: timed usability evidence, service-only validation gate, immutable review snapshots | Implementation complete; real beta evidence pending |

## Completion plan

| Phase | Scope | Status |
| --- | --- | --- |
| 1 | Foundation: toolchain, baseline screens, source documents, release guard, database tests | Complete |
| 2 | Core flow: in-app notifications, trip editing and cancellation, leaving a trip, cancellation windows, hiding past trips, profile editing | Implemented; Android push is built but not yet tested on a device, and iOS push needs a paid Apple account |
| 3 | Trust and legal: occupation, Instagram, trust facts, terms, consent, account deletion, account switching | Implemented; legal text is a draft pending review, and structured join details and host filters and tags move to Phase 5 |
| 4 | Match the mockups: shared design pieces, then Explore, Trip details, Create trip, and Join request; French and English | Implemented; French awaits native review, push text and server errors are still English, and Join request context needs Phase 5 data |
| 5 | Discovery and logistics: map view, place search with coordinates, pre-filled booking links, saved trips, structured join details, host background filter | Implemented; the map and booking links are not yet tried on a device, and place search covers a built-in list of Moroccan places |
| 6 | Beta: crash reporting, security audit, staging, signing, real KPI evidence | Not started |

## Product decisions

These settle or narrow specification items for the PoC:

- Instagram is an optional, unverified handle, not OAuth.
- Occupation is self-declared and carries no verified badge.
- Late withdrawals are handled by a cancellation window, not deposits. Leaving
  is free until seven days before departure; later departures are still allowed,
  and are recorded and reported to the host.
- Joining part of a trip is deferred; only whole trips can be joined.
- Reputation scores are deferred; profiles show facts such as trips hosted.
- Trips use photos where available and the mockup illustration as a fallback.
- Translations are set up for French and English; Arabic follows the beta.
- Shared costs are split equally. The mockup's 3,450 to 2,780 example is
  illustrative, because an equal split from two to three people gives 2,300.

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
