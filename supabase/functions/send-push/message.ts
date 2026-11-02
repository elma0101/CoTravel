export interface NotificationRecord {
  id: string;
  user_id: string;
  kind: string;
  trip_id: string | null;
  trip_title: string;
  actor_name: string | null;
}

// Mirrors AppNotification.message in the app. A kind this function does not know
// sends nothing rather than a blank alert.
export function messageFor(record: NotificationRecord): string | null {
  const actor = record.actor_name ?? "Someone";
  const trip = record.trip_title;
  switch (record.kind) {
    case "join_request_received":
      return `${actor} asked to join ${trip}.`;
    case "request_approved":
      return `${actor} approved your request for ${trip}. Confirm to lock your place.`;
    case "request_declined":
      return `Your request for ${trip} was not accepted.`;
    case "traveler_confirmed":
      return `${actor} confirmed their place on ${trip}.`;
    case "traveler_declined":
      return `${actor} declined the invitation to ${trip}.`;
    case "traveler_withdrew":
      return `${actor} withdrew their request for ${trip}.`;
    case "traveler_left":
      return `${actor} left ${trip}.`;
    case "traveler_left_late":
      return `${actor} left ${trip} within 7 days of departure.`;
    case "trip_updated":
      return `${actor} updated ${trip}. Check the latest plan.`;
    case "trip_cancelled":
      return `${actor} cancelled ${trip}.`;
    default:
      return null;
  }
}

export function fcmMessage(
  record: NotificationRecord,
  body: string,
  token: string,
) {
  return {
    message: {
      token,
      notification: { title: "CoTravel", body },
      // FCM accepts only string values, so a missing trip is left out.
      data: {
        notification_id: record.id,
        kind: record.kind,
        ...(record.trip_id ? { trip_id: record.trip_id } : {}),
      },
      android: { priority: "HIGH" },
    },
  };
}

// True when FCM says the token will never work again, so its row can be deleted.
// Other failures may be temporary or our own fault and must keep the token.
export function isDeadToken(status: number, responseBody: string): boolean {
  if (status === 404) {
    return true;
  }
  return status === 400 && responseBody.includes("UNREGISTERED");
}

export function secretsMatch(provided: string, expected: string): boolean {
  const left = new TextEncoder().encode(provided);
  const right = new TextEncoder().encode(expected);
  if (left.length !== right.length) {
    return false;
  }
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}
