# CoTravel v0 analytics contract

The app records only whitelisted product events with small JSON metadata. Event
capture is best-effort and never blocks a user workflow. The client cannot read
the event table or choose another actor ID.

| Event | Trigger | KPI use |
| --- | --- | --- |
| `profile_completed` | Onboarding profile saved | User adoption funnel |
| `profile_verified` | LinkedIn verification observed in the session | Verified profile count |
| `trip_builder_opened` | Host opens the itinerary builder | Start of trip-creation timing sample |
| `trip_published` | Valid itinerary published | Trip creation rate |
| `join_request_submitted` | Traveler introduction accepted | Request funnel |
| `trip_place_confirmed` | Traveler completes mutual approval | Confirmation conversion |
| `group_created` | Confirmation opens or expands a trip group | Group match rate by distinct trip |
| `conversation_opened` | Confirmed member opens group chat | Coordination engagement |
| `safety_report_submitted` | Report stored | Safety operations volume |
| `user_blocked` | Block stored | Safety operations volume |

`preview_signed_in` exists only for local preview evaluation and should be
excluded from production adoption KPIs.

Allowed metadata is intentionally coarse: capacity, travel style, and report
reason. Names, bios, message bodies, report details, emails, exact locations,
and booking URLs must never be added to analytics properties.

`trip_builder_opened` contains no trip ID or metadata. The service-only PoC
evidence view pairs it with the next hosted `trip_published` event within two
hours using server timestamps. This measures the complete form experience
without sending a user-supplied duration or field contents.
