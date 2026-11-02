# Experience plan

The six build phases gave CoTravel every core feature. This plan makes those
features feel quick and playful: fewer forms, more tapping and swiping, and a
smooth path from one section to the next.

## Rules

- **One feature at a time.** A feature is finished only when it meets its
  "done when" checks on a real phone and the product owner signs it off. Only
  then does the next one start.
- **Reshape, don't rebuild.** The database, rules and controllers already work
  and are tested. Each feature mostly changes screens and flow, and keeps the
  logic underneath.
- **Same loop for every feature:**
  1. Walk through the current flow on the phone and count screens, taps and
     typed fields.
  2. Agree on a short sketch of the new flow before writing code.
  3. Build it, with tests.
  4. Try it on the phone and fix what feels slow or confusing.
  5. Sign off.
- **Polish is part of each feature, not a phase at the end:** transitions,
  haptics, loading placeholders, empty states and a clear success moment.
- **Not now:** iPhone, legal review, store listings, Arabic, partial trips,
  reputation scores.

## Feature 0: A stable base

Make sure what exists works on the phone before changing it.

- Bring staging up to date (`supabase db push --linked`).
- Try the untested parts on the phone: photos, place search, departure
  points, the trip map, booking links, and the profile kept after LinkedIn.
- Fix anything broken.

**Done when** each of those works once on the phone against staging.

## Feature 1: Sign up and get verified

From a long profile form to a few quick screens.

- One question per screen, answered mostly by tapping: name, photo, home city,
  travel styles, languages.
- Name and photo prefilled from LinkedIn when possible.
- Bio, occupation and Instagram become optional, added later from the profile.
- A progress bar and a welcoming finish that leads straight into Explore.

**Done when** a new user goes from opening the app to Explore in under 60
seconds and types no more than their name.

## Feature 2: Create a trip

From three dense form steps to a guided flow.

- Full-screen steps: where to, when, how many people, budget, photo.
- Place search, date range, a seat counter and budget presets instead of
  free-text fields.
- The title and summary are suggested and can be edited.
- Stop details (type, transport, duration, notes) move to "add details later".
- A preview card before publishing, then a share moment.

**Done when** a host publishes a simple trip in under 60 seconds and types
nothing beyond the destination.

## Feature 3: Discover trips

From a list with a filter form to browsing that is fun.

- Full-screen trip cards: swipe to save or skip, tap to open.
- Switch between cards and the map.
- Quick filter chips (dates, destination, style, verified hosts) instead of a
  form.

**Done when** someone finds and opens a trip that matches what they want in
three taps or fewer from opening the app.

## Feature 4: Join and decide

The core match moment, with live status like a ride app.

- Ask to join with one tap and an optional short message.
- Hosts see incoming requests as cards to accept or decline with one tap.
- Both sides see a live status: Requested, Accepted, Confirmed, Group open.
- Android push notifications for each change, so nobody has to check the app.

**Done when**, with two phones, a request, a decision and the confirmation
each take one tap, and the other phone is notified within seconds.

## Feature 5: The trip home

Everything about a confirmed trip in one place.

- One screen with the group chat, the plan, each person's share and the
  members, plus a countdown to departure.
- Booking links and cost changes reachable from there, not from separate tabs.

**Done when** a confirmed traveler reaches chat, plan or costs in one tap from
the trip home.

## Feature 6: Try it with real people

- Three to five people go through the main journeys on their own phones.
- Fix where they hesitate, then compare the counts with the walk-throughs.

**Done when** everyone finishes the main journeys without help.
