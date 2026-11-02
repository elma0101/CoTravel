-- Supabase projects may grant anon/authenticated broad default privileges to
-- newly created objects. RLS still protects rows, but explicit least-privilege
-- grants keep service-only RPCs and tables out of the public API surface.

revoke all on table
  public.profiles,
  public.trips,
  public.trip_stops,
  public.trip_join_requests,
  public.trip_conversations,
  public.conversation_members,
  public.chat_messages,
  public.trip_logistics,
  public.user_blocks,
  public.safety_reports,
  public.analytics_events,
  public.beta_feedback,
  public.poc_validation_snapshots,
  public.app_environment_controls,
  public.staging_verification_allowlist
from anon, authenticated;
grant select on table
  public.profiles,
  public.trips,
  public.trip_stops,
  public.trip_join_requests,
  public.trip_conversations,
  public.conversation_members,
  public.chat_messages,
  public.trip_logistics
to authenticated;
revoke all on table
  public.moderation_report_queue,
  public.beta_kpi_dashboard,
  public.poc_evidence_dashboard
from anon, authenticated;
grant select, update on table public.safety_reports to service_role;
grant select on table
  public.profiles,
  public.trips,
  public.trip_stops,
  public.trip_join_requests,
  public.trip_conversations,
  public.user_blocks,
  public.analytics_events,
  public.beta_feedback,
  public.poc_validation_snapshots,
  public.moderation_report_queue,
  public.beta_kpi_dashboard,
  public.poc_evidence_dashboard
to service_role;
grant select, insert, update, delete on table
  public.app_environment_controls,
  public.staging_verification_allowlist
to service_role;
revoke all on sequence
  public.analytics_events_id_seq,
  public.trip_stops_id_seq
from anon, authenticated;
revoke execute on all functions in schema public
from public, anon, authenticated;
grant execute on function public.block_user(uuid) to authenticated;
grant execute on function public.complete_profile(
  text,
  text,
  text,
  text[],
  text[],
  text
) to authenticated;
grant execute on function public.confirm_join_request(uuid, boolean)
to authenticated;
grant execute on function public.create_join_request(uuid, text)
to authenticated;
grant execute on function public.create_trip(
  text,
  text,
  date,
  date,
  jsonb,
  smallint,
  numeric,
  numeric,
  text,
  text,
  text
) to authenticated;
grant execute on function public.is_confirmed_trip_member(uuid)
to authenticated;
grant execute on function public.is_conversation_member(uuid)
to authenticated;
grant execute on function public.is_user_blocked_between(uuid, uuid)
to authenticated;
grant execute on function public.list_chat_messages(
  uuid,
  timestamptz,
  uuid,
  integer
) to authenticated;
grant execute on function public.mark_conversation_read(uuid)
to authenticated;
grant execute on function public.mark_conversation_read_through(
  uuid,
  timestamptz
) to authenticated;
grant execute on function public.my_beta_feedback() to authenticated;
grant execute on function public.my_blocked_users() to authenticated;
grant execute on function public.my_safety_reports() to authenticated;
grant execute on function public.my_trip_conversations() to authenticated;
grant execute on function public.review_join_request(uuid, boolean)
to authenticated;
grant execute on function public.save_trip_logistics(
  uuid,
  numeric,
  numeric,
  text,
  text,
  text,
  text,
  text
) to authenticated;
grant execute on function public.send_chat_message(uuid, text)
to authenticated;
grant execute on function public.send_chat_message_v2(uuid, text, text)
to authenticated;
grant execute on function public.submit_beta_feedback(text, smallint, text)
to authenticated;
grant execute on function public.submit_safety_report(
  uuid,
  uuid,
  text,
  text
) to authenticated;
grant execute on function public.sync_my_linkedin_verification()
to authenticated;
grant execute on function public.track_product_event(text, uuid, jsonb)
to authenticated;
grant execute on function public.unblock_user(uuid) to authenticated;
grant execute on function public.withdraw_join_request(uuid)
to authenticated;
grant execute on function public.capture_poc_validation_snapshot(
  boolean,
  boolean,
  integer,
  text
) to service_role;
grant execute on function public.seed_controlled_beta_trips(uuid, text)
to service_role;
alter default privileges for role postgres in schema public
revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public
revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public
revoke execute on functions from public, anon, authenticated;
