# PoC validation and expansion-readiness gate

Milestone 9 turns the specification's validation checklist into reviewable
evidence. It does not declare the product validated before the controlled beta
has run, and it does not add features outside the PoC boundary.

## Evidence matrix

| Functional checkpoint | Automated evidence | Real-beta evidence |
| --- | --- | --- |
| Email onboarding and social identity | Auth/profile tests and RLS audit | Two-account staging audit plus verified-profile count |
| Complete itinerary in under three minutes | Builder and publication event contract | At least five paired attempts; at least 80% within 180 seconds |
| Discovery by destination, dates, and host background | Filter unit and widget tests | Participant completes the discovery task |
| Join request and host decision | Request state-machine and authorization tests | At least one real request and one confirmed group |
| Closed group chat after acceptance | Conversation creation and membership tests | Confirmed group has a private conversation |
| Dynamic per-person costs | Cost engine tests across group sizes | Participant verifies the displayed split changes correctly |

The five-sample and 80% itinerary-timing rule is an evidence-quality guardrail,
not a new product KPI. Timing uses server event timestamps: the latest
`trip_builder_opened` event is paired with a hosted `trip_published` event when
they are no more than two hours apart. Form contents and exact route data are
not added to analytics.

## Read the live evidence

Use only a trusted service-role context such as the staging SQL editor:

```sql
select * from public.poc_evidence_dashboard;
```

`poc_data_gate_ready` requires:

- all four specification KPIs;
- the controlled-beta feedback sample guardrail;
- adequate itinerary timing evidence; and
- observed request, confirmation, and conversation data.

Automated test results, the manual security audit, release blockers, discovery
task observation, and dynamic-cost observation remain outside the database and
must be reviewed by a person.

## Capture an immutable review record

After recording the CI run, security-audit evidence, and blocker list, capture
a review snapshot:

```sql
select public.capture_poc_validation_snapshot(
  p_automated_checks_passed := true,
  p_security_audit_passed := true,
  p_open_release_blockers := 0,
  p_note := 'Review date, CI run URL, cohort, and evidence folder reference.'
);
```

Never pass `true` based on preview data or an unexecuted checklist. Snapshots
are append-only through the application permission model: service-role users
can read them but cannot update or delete them. The capture function is the
only granted write path.

Review history with:

```sql
select *
from public.poc_validation_snapshots
order by captured_at desc;
```

The strongest database outcome is `ready_for_stakeholder_review`. It is not an
automatic production launch or investment recommendation.

## Go/no-go review

The review owner must verify all of the following before recommending an
expansion discussion:

1. `poc_data_gate_ready` is true using real staging-beta data.
2. The full CI run passed for the exact candidate build.
3. Every scenario in `security-audit.md` passed with real accounts.
4. No unresolved high-severity safety issue or release blocker remains.
5. Discovery and dynamic-cost tasks were observed with representative users.
6. The beta cohort and feedback solicitation were not biased toward positive
   respondents.

If any item is false or unsupported, capture `not_ready`, document the gap,
and choose a focused remediation milestone. Do not broaden the roadmap merely
to conceal a failed validation signal.
