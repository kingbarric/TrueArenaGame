# Huud room and member nudges

The October 15 update fixes sofa seating, uses the PlayHuud orange palette,
adds faster walking through a doorway, and limits room avatars to present members.
Offline members appear under “Away from The Huud”; tapping a member offers a
nudge. The table's Start a game button opens the Games tab. Registration now
saves a male/female starter avatar before username setup.

Nudges require both people to belong to a live Huud, respect blocks and muted
Huuds, and share a five-minute cooldown per recipient across all senders.
Push invitations deep-link into the Huud. Firebase delivery is best effort.

## Test notifications

Test notifications are opt-in. On 15 October 2026, following explicit approval,
Firebase was enabled for exactly one approved test account. The credential and
recipient UUID live only in ignored test configuration and the private server
environment. Firebase initialization and the one-account restriction were
verified; physical notification receipt still needs a device check.

Optional test push requires both server-side settings in the test environment:

- `TEST_FIREBASE_CREDENTIALS_BASE64`: an explicitly approved Firebase credential.
- `TEST_PUSH_ALLOWED_USER_IDS`: comma-separated UUIDs of approved test recipients.

An empty allowlist blocks all test push, including broadcasts and call alerts.
Production notification behaviour is unchanged. Never use a production-wide
recipient list or print credential values. Changing these settings needs a test
backend recreation; it does not need a new iOS build.


## Room recovery and layout

Drag/zoom instructions appear under The Huud title. Away from The Huud is a
pinned footer with readable dark text and a collapsed dropdown. Opening it shows
a vertical overlay of at most five away members at once, with scrolling for
larger rosters. It does not shrink the room. The microphone and Invite controls
sit beside the code inside the orange card. The repeated people/privacy line
and online-name chips below the scene are removed; the live People canvas fills
the remaining screen height. Names remain above the avatars.

“Away” describes presence in the live Huud, not whether the person's phone has
internet. The app sends a heartbeat every 45 seconds; the member response requires
activity within the last 75 seconds, an active live seat, and a foreground app.
Connected game, inbox and voice activity also refreshes the activity record.
The room refreshes its member data every eight seconds.

The room automatically retries renderer failures with bounded backoff, recreates
a failed WebView, detects stalled loads, and resumes retries when the app returns
to the foreground. Retry timers stop when the screen is disposed. API requests
and token refreshes time out after 30 seconds rather than hanging indefinitely.
