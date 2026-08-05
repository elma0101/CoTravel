import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hardening migration keeps private tables behind RPC boundaries', () {
    final sql = File(
      'supabase/migrations/20260805170000_create_safety_hardening.sql',
    ).readAsStringSync();

    expect(
      sql,
      contains('alter table public.safety_reports enable row level security'),
    );
    expect(
      sql,
      contains('alter table public.analytics_events enable row level security'),
    );
    expect(sql, contains('trip_join_requests_prevent_blocked_users'));
    expect(sql, contains('is_user_blocked_between'));
    expect(
      sql,
      contains(
        'revoke all on public.moderation_report_queue from anon, authenticated',
      ),
    );
    expect(
      sql,
      isNot(
        contains('grant select on public.analytics_events to authenticated'),
      ),
    );
    expect(
      sql,
      contains('grant select on public.analytics_events to service_role'),
    );
  });
}
