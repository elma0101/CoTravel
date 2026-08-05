import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('controlled beta migration protects feedback and KPI access', () {
    final sql = File(
      'supabase/migrations/20260805190000_create_controlled_beta.sql',
    ).readAsStringSync();

    expect(
      sql,
      contains('alter table public.beta_feedback enable row level security'),
    );
    expect(
      sql,
      contains('revoke all on public.beta_feedback from anon, authenticated'),
    );
    expect(
      sql,
      contains(
        'revoke all on public.beta_kpi_dashboard from anon, authenticated',
      ),
    );
    expect(
      sql,
      contains('grant select on public.beta_kpi_dashboard to service_role'),
    );
    expect(sql, contains('verified_profiles >= 50'));
    expect(sql, contains('published_itineraries >= 15'));
    expect(sql, contains('from public.trip_stops'));
    expect(sql, contains('matched_itinerary_percent >= 30'));
    expect(sql, contains('positive_safe_informed_percent > 80'));
    expect(sql, contains('distinct on (user_id)'));
  });

  test('staging seed is guarded, idempotent, and contains 15 trips', () {
    final sql = File(
      'supabase/migrations/20260805190000_create_controlled_beta.sql',
    ).readAsStringSync();

    expect(RegExp(r'\{"title":"\[Beta\]').allMatches(sql), hasLength(15));
    expect(sql, contains("if p_environment <> 'staging'"));
    expect(sql, contains('and title = seed_trip.item'));
    expect(
      sql,
      contains(
        'grant execute on function public.seed_controlled_beta_trips(uuid, text)\nto service_role',
      ),
    );
  });
}
