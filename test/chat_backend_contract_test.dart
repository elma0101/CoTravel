import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('completed chat migration keeps history and sends member-gated', () {
    final sql = File(
      'supabase/migrations/20260806010000_complete_trip_chat.sql',
    ).readAsStringSync();

    expect(sql, contains('public.is_conversation_member(p_conversation_id)'));
    expect(sql, contains('public.list_chat_messages'));
    expect(sql, contains('public.send_chat_message_v2'));
    expect(sql, contains('public.mark_conversation_read_through'));
    expect(sql, contains('chat_messages_sender_client_id_unique'));
    expect(sql, contains('tablename = \'conversation_members\''));
    expect(
      sql,
      contains(
        'grant execute on function public.send_chat_message_v2(uuid, text, text)',
      ),
    );
  });

  test('completed chat RPCs are exposed only to authenticated clients', () {
    final sql = File(
      'supabase/migrations/20260806010000_complete_trip_chat.sql',
    ).readAsStringSync();

    expect(
      sql,
      contains(
        'grant execute on function public.send_chat_message_v2(uuid, text, text)\n'
        'to authenticated',
      ),
    );
    expect(
      sql,
      contains(
        'revoke all on function public.send_chat_message_v2(uuid, text, text)\n'
        'from public',
      ),
    );
    expect(sql, isNot(contains('to anon')));
  });
}
