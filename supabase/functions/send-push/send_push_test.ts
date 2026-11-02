import { assertEquals } from "jsr:@std/assert@1";
import { deliver, type PushBackend } from "./deliver.ts";
import {
  fcmMessage,
  isDeadToken,
  messageFor,
  type NotificationRecord,
  secretsMatch,
} from "./message.ts";

const messageKinds = {
  join_request_received: 1,
  request_approved: 1,
  request_declined: 1,
  traveler_confirmed: 1,
  traveler_declined: 1,
  traveler_withdrew: 1,
  traveler_left: 1,
  traveler_left_late: 1,
  trip_updated: 1,
  trip_cancelled: 1,
};

const record: NotificationRecord = {
  id: "n1",
  user_id: "u1",
  kind: "trip_cancelled",
  trip_id: "t1",
  trip_title: "Atlas weekend",
  actor_name: "Amina",
};

function backendWith(responses: Record<string, { status: number; body: string }>) {
  const deleted: string[] = [];
  const backend: PushBackend = {
    tokensFor: () =>
      Promise.resolve(
        Object.keys(responses).map((token) => ({
          token,
          language: "en" as const,
        })),
      ),
    deleteToken: (token) => {
      deleted.push(token);
      return Promise.resolve();
    },
    send: (message) => {
      const { token } = (message as { message: { token: string } }).message;
      return Promise.resolve(responses[token]);
    },
  };
  return { backend, deleted };
}

Deno.test("every kind the database allows has a message", () => {
  const migration = Deno.readTextFileSync(
    new URL(
      "../../migrations/20260806050000_core_flow.sql",
      import.meta.url,
    ),
  );
  const constraint = migration.match(
    /notifications_kind_valid check \(([\s\S]*?)\n  \)/,
  )![1];
  const kinds = [...constraint.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
  assertEquals(kinds.length, 10);
  for (const kind of kinds) {
    assertEquals(typeof messageFor({ ...record, kind }), "string", kind);
  }
});

Deno.test("each device gets its own language", async () => {
  const bodies: Record<string, string> = {};
  const backend: PushBackend = {
    tokensFor: () =>
      Promise.resolve([
        { token: "fr-phone", language: "fr" as const },
        { token: "en-phone", language: "en" as const },
      ]),
    deleteToken: () => Promise.resolve(),
    send: (message) => {
      const { token, notification } = (message as {
        message: { token: string; notification: { body: string } };
      }).message;
      bodies[token] = notification.body;
      return Promise.resolve({ status: 200, body: "{}" });
    },
  };

  await deliver(record, backend);

  assertEquals(bodies["fr-phone"], "Amina a annulé Atlas weekend.");
  assertEquals(bodies["en-phone"], "Amina cancelled Atlas weekend.");
});

Deno.test("every kind has French too", () => {
  for (const kind of Object.keys(messageKinds)) {
    assertEquals(typeof messageFor({ ...record, kind }, "fr"), "string", kind);
  }
});

Deno.test("an unknown kind sends nothing", async () => {
  const { backend } = backendWith({ a: { status: 200, body: "" } });
  const result = await deliver({ ...record, kind: "new_kind" }, backend);
  assertEquals(result, { sent: 0, failed: 0, removed: 0 });
});

Deno.test("a missing trip is left out of the data", () => {
  const { message } = fcmMessage({ ...record, trip_id: null }, "body", "token");
  assertEquals(message.data, { notification_id: "n1", kind: "trip_cancelled" });
});

Deno.test("only dead tokens are removed", async () => {
  const { backend, deleted } = backendWith({
    good: { status: 200, body: "{}" },
    gone: { status: 404, body: "" },
    outage: { status: 503, body: "" },
    invalid: { status: 400, body: "INVALID_ARGUMENT" },
  });
  const result = await deliver(record, backend);
  assertEquals(result, { sent: 1, failed: 2, removed: 1 });
  assertEquals(deleted, ["gone"]);
});

Deno.test("unregistered tokens are recognised", () => {
  assertEquals(isDeadToken(400, '{"errorCode":"UNREGISTERED"}'), true);
  assertEquals(isDeadToken(401, "UNREGISTERED"), false);
});

Deno.test("the webhook secret must match exactly", () => {
  assertEquals(secretsMatch("secret", "secret"), true);
  assertEquals(secretsMatch("secreT", "secret"), false);
  assertEquals(secretsMatch("", "secret"), false);
});
