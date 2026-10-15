# Huud room and member nudges

The October 15 update fixes sofa seating, uses the PlayHuud orange palette,
adds faster walking through a doorway, and limits room avatars to present members.
Offline members appear under “Away from The Huud”; tapping a member offers a
nudge. The table's Start a game button opens the S Games tab. Registration now
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
pinned footer with readable dark text and horizontally scrolling offline names.
The room automatically retries renderer failures with bounded backoff, recreates
a failed WebView, detects stalled loads, and resumes retries when the app returns
to the foreground. Retry timers stop when the screen is disposed. API requests
and token refreshes time out after 30 seconds rather than hanging indefinitely.
