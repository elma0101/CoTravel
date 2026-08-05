# Controlled beta runbook

Milestone 8 is implemented in the repository but is not externally activated.
Activation requires a Supabase staging project and private Apple and Google
signing credentials. Never place a service-role key or store credential in the
Flutter app, a committed configuration file, or a CI artifact.

## Validation targets

The controlled beta evaluates the four product-specification targets:

| Measure | Target | Repository definition |
| --- | ---: | --- |
| Verified profiles | 50 | Onboarding complete and LinkedIn verification present |
| Published complete itineraries | 15 | Trip status is `published` and at least one ordered stop exists |
| Itineraries with a match | 30% or more | Published trips with at least one confirmed traveler |
| Positive safe-and-informed feedback | More than 80% | Latest response per account scored 4 or 5 out of 5 |

The dashboard also exposes `feedback_sample_ready` at 20 responses. This is an
operational guardrail for interpreting the percentage, not a specification
target. Do not report the sentiment target as validated before that flag is
true.

The KPI dashboard is intentionally service-only. Read it from the Supabase SQL
editor or another trusted backend context:

```sql
select * from public.beta_kpi_dashboard;
```

Do not expose this view through the mobile client. Each account's latest
feedback response is used, which prevents repeated submissions by one tester
from multiplying their weight.

## 1. Activate isolated staging

1. Create a dedicated Supabase staging project; never use production for beta
   setup experiments.
2. Apply every migration in `supabase/migrations` in filename order.
3. Configure the mobile callback URL `com.cotravel.app://login-callback` and
   LinkedIn OIDC in Supabase Auth.
4. Copy `config/staging.example.json` to the ignored
   `config/staging.json` and add only the staging URL and publishable key.
5. Run every authorization scenario in `security-audit.md` with at least two
   real staging accounts.

## 2. Prepare representative content

Create one complete, LinkedIn-verified staging host, then invoke the
service-role-only seed function from the staging SQL editor:

```sql
select public.seed_controlled_beta_trips(
  '<VERIFIED_STAGING_HOST_UUID>'::uuid,
  'staging'
);
```

The function idempotently creates up to 15 clearly labelled fictional Morocco
itineraries, with future dates and no personal data. A second invocation skips
the existing active seed trips. Review all routes, dates, and estimates before
showing them to testers. These trips can satisfy content availability, but do
not seed fake profiles, feedback, confirmations, or KPI success.

## 3. Build and distribute

The app identifier is fixed as `com.cotravel.app` on Android and iOS. Confirm
that this is the intended permanent identifier before the first Play upload,
because Play fixes the package name when an artifact is uploaded.

CI can be started manually and stores a debug Android APK, test coverage, and
an unsigned iOS `.app` for 14 days. They are QA artifacts only. The unsigned
iOS artifact cannot be installed through TestFlight, and no debug-signed or
unsigned Android artifact is acceptable for Play.

For Android:

1. Create and protect a beta upload keystore outside the repository.
2. Create the ignored `android/key.properties`; the Gradle release setup loads
   it when present and deliberately has no debug-key fallback.
3. Build with
   `flutter build appbundle --release --dart-define-from-file=config/staging.json`.
4. Upload the signed AAB to Google Play internal testing, add the tester list,
   add the in-app feedback route as the feedback channel, and share the opt-in
   URL. Google recommends beginning with internal testing, which supports up to
   100 testers: <https://support.google.com/googleplay/android-developer/answer/9845334>.

For iOS:

1. Install full Xcode and CocoaPods, register `com.cotravel.app`, and select the
   correct Apple team and signing profile.
2. Build/archive with the staging configuration and upload the signed archive
   through Xcode or the approved CI signing workflow.
3. Add beta test information and a monitored feedback address, then invite the
   internal cohort. External testers additionally require beta app review
   information: <https://developer.apple.com/testflight/>.

GitHub workflow artifacts are retained only to support QA handoff, following
GitHub's artifact model: <https://docs.github.com/en/actions/concepts/workflows-and-actions/workflow-artifacts>.

## 4. Run the cohort

1. Recruit real participants and obtain clear consent for beta analytics and
   account-linked feedback.
2. Start with 10 to 15 internal testers for a smoke wave, then expand toward 50
   verified profiles after crash, auth, and moderation checks remain healthy.
3. Ask each tester to complete one realistic path: discover and request, host
   and review, confirm and coordinate, or update trip logistics.
4. After the task, direct them to **Profile → Beta feedback**. Avoid prompting
   only satisfied users.
5. Review safety reports daily using the manual moderation runbook. Pause
   invitations for any authorization leak, widespread login failure, data-loss
   defect, or unresolved high-severity safety report.
6. Check the service-only KPI view at a consistent cadence and record dated
   snapshots outside the app.

## 5. Exit decision

Proceed from controlled beta only when all specification booleans in the KPI
view are true, `feedback_sample_ready` is true, the security audit passes, and
no high-severity release blocker remains. A percentage based on an inadequate
sample, seeded confirmations, or solicited-positive-only feedback is not valid
evidence. If a target misses, use feedback comments and task area to choose the
next focused iteration rather than broadening the product scope.
