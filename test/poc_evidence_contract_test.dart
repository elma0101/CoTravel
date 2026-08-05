import 'dart:io';

import 'package:cotravel_app/core/analytics/product_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/20260805210000_create_poc_evidence_gate.sql',
    ).readAsStringSync();
  });

  test('trip builder timing event is privacy-minimized', () {
    expect(ProductEvent.tripBuilderOpened.databaseValue, 'trip_builder_opened');
    expect(sql, contains("'trip_builder_opened'"));
    expect(sql, contains('Trip builder timing events cannot contain metadata'));
    expect(sql, contains("interval '2 hours'"));
    expect(sql, contains('completion_seconds <= 180'));
  });

  test('PoC evidence dashboard is service-only and guarded', () {
    expect(
      sql,
      contains(
        'revoke all on public.poc_evidence_dashboard from anon, authenticated',
      ),
    );
    expect(
      sql,
      contains('grant select on public.poc_evidence_dashboard to service_role'),
    );
    expect(sql, contains('itinerary_timing_sample_count >= 5'));
    expect(sql, contains('itinerary_under_three_minutes_percent >= 80'));
    expect(sql, contains('beta.all_spec_targets_met'));
    expect(sql, contains('beta.feedback_sample_ready'));
    expect(sql, contains('workflow_data_evidence_ready'));
  });

  test('review snapshots are append-only and never auto-approve expansion', () {
    expect(
      sql,
      contains(
        'alter table public.poc_validation_snapshots enable row level security',
      ),
    );
    expect(
      sql,
      contains(
        'revoke all on public.poc_validation_snapshots\nfrom anon, authenticated, service_role',
      ),
    );
    expect(
      sql,
      contains(
        'grant select on public.poc_validation_snapshots to service_role',
      ),
    );
    expect(sql, isNot(contains('grant update')));
    expect(sql, isNot(contains('grant delete')));
    expect(sql, contains("then 'ready_for_stakeholder_review'"));
    expect(sql, isNot(contains("'approved_for_expansion'")));
  });
}
