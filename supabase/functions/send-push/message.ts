export interface NotificationRecord {
  id: string;
  user_id: string;
  kind: string;
  trip_id: string | null;
  trip_title: string;
  actor_name: string | null;
}

export type PushLanguage = "en" | "fr";

const messages: Record<
  PushLanguage,
  { someone: string; byKind: Record<string, (actor: string, trip: string) => string> }
> = {
  en: {
    someone: "Someone",
    byKind: {
      join_request_received: (actor, trip) => `${actor} asked to join ${trip}.`,
      request_approved: (actor, trip) =>
        `${actor} approved your request for ${trip}. Confirm to lock your place.`,
      request_declined: (_, trip) =>
        `Your request for ${trip} was not accepted.`,
      traveler_confirmed: (actor, trip) =>
        `${actor} confirmed their place on ${trip}.`,
      traveler_declined: (actor, trip) =>
        `${actor} declined the invitation to ${trip}.`,
      traveler_withdrew: (actor, trip) =>
        `${actor} withdrew their request for ${trip}.`,
      traveler_left: (actor, trip) => `${actor} left ${trip}.`,
      traveler_left_late: (actor, trip) =>
        `${actor} left ${trip} within 7 days of departure.`,
      trip_updated: (actor, trip) =>
        `${actor} updated ${trip}. Check the latest plan.`,
      trip_cancelled: (actor, trip) => `${actor} cancelled ${trip}.`,
    },
  },
  fr: {
    someone: "Quelqu’un",
    byKind: {
      join_request_received: (actor, trip) =>
        `${actor} a demandé à rejoindre ${trip}.`,
      request_approved: (actor, trip) =>
        `${actor} a approuvé votre demande pour ${trip}. Confirmez pour réserver votre place.`,
      request_declined: (_, trip) =>
        `Votre demande pour ${trip} n’a pas été acceptée.`,
      traveler_confirmed: (actor, trip) =>
        `${actor} a confirmé sa place pour ${trip}.`,
      traveler_declined: (actor, trip) =>
        `${actor} a refusé l’invitation pour ${trip}.`,
      traveler_withdrew: (actor, trip) =>
        `${actor} a retiré sa demande pour ${trip}.`,
      traveler_left: (actor, trip) => `${actor} a quitté ${trip}.`,
      traveler_left_late: (actor, trip) =>
        `${actor} a quitté ${trip} moins de 7 jours avant le départ.`,
      trip_updated: (actor, trip) =>
        `${actor} a modifié ${trip}. Consultez le dernier programme.`,
      trip_cancelled: (actor, trip) => `${actor} a annulé ${trip}.`,
    },
  },
};

// Mirrors AppNotification.message in the app. A kind this function does not know
// sends nothing rather than a blank alert.
export function messageFor(
  record: NotificationRecord,
  language: PushLanguage = "en",
): string | null {
  const copy = messages[language];
  const build = copy.byKind[record.kind];
  return build
    ? build(record.actor_name ?? copy.someone, record.trip_title)
    : null;
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
