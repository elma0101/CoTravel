# CoTravel manual moderation runbook

Milestone 7 intentionally uses human review instead of automated enforcement.
The service-role-only `moderation_report_queue` view contains submitted report
context and private moderator fields.

## Triage workflow

1. Open reports with `status = 'submitted'`, oldest first.
2. Set the selected row to `in_review` and record the review start in
   `reviewed_at`.
3. Review only the minimum necessary profile, trip, request, and conversation
   context. Never copy personal data into external notes.
4. For credible immediate-risk content, preserve evidence and follow the
   organization escalation procedure. The in-app report channel is not an
   emergency service.
5. Set the report to `resolved` when action was taken, or `dismissed` when the
   available evidence does not support action. Keep `moderator_notes` factual,
   concise, and free of speculation.
6. Do not disclose the reporter's identity to the reported account.

## Minimum evidence handling

- Keep report details and relevant database records unchanged.
- Do not delete chat evidence as the first moderation action.
- Use account suspension controls outside this PoC only with an approved
  operator procedure.
- Restrict the service-role key to trusted server/operator environments; it
  must never appear in Flutter configuration or source code.

## Status meanings

- `submitted`: waiting for a moderator.
- `in_review`: a moderator owns the case.
- `resolved`: review completed and an action or safety response was recorded.
- `dismissed`: review completed without enforcement.
