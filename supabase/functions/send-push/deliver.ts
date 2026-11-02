import {
  fcmMessage,
  isDeadToken,
  messageFor,
  type NotificationRecord,
} from "./message.ts";

export interface PushBackend {
  tokensFor(userId: string): Promise<string[]>;
  deleteToken(token: string): Promise<void>;
  send(message: unknown): Promise<{ status: number; body: string }>;
}

export async function deliver(
  record: NotificationRecord,
  backend: PushBackend,
): Promise<{ sent: number; failed: number; removed: number }> {
  const result = { sent: 0, failed: 0, removed: 0 };
  const body = messageFor(record);
  if (body === null) {
    return result;
  }

  for (const token of await backend.tokensFor(record.user_id)) {
    const response = await backend.send(fcmMessage(record, body, token));
    if (response.status >= 200 && response.status < 300) {
      result.sent++;
    } else if (isDeadToken(response.status, response.body)) {
      await backend.deleteToken(token);
      result.removed++;
    } else {
      result.failed++;
      console.error(`FCM send failed with status ${response.status}`);
    }
  }
  return result;
}
