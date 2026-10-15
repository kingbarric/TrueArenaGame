# Huud room and member nudges

The October 15 update fixes sofa seating, uses the PlayHuud orange palette,
adds faster walking through a doorway, and limits room avatars to present members.
Offline members appear under “Away from The Huud”; tapping a member offers a
nudge. The table's Start a game button opens the Game tab. Registration now
saves a male/female starter avatar before username setup.

Nudges require both people to belong to a live Huud, respect blocks and muted
Huuds, and share a five-minute cooldown per recipient across all senders.
Push invitations deep-link into the Huud. Firebase delivery is best effort.

## Test notifications

The existing test deployment intentionally disables external notifications.
No Firebase credential has been enabled by this update.

Optional test push requires both server-side settings in the test environment:

- `TEST_FIREBASE_CREDENTIALS_BASE64`: an explicitly approved Firebase credential.
- `TEST_PUSH_ALLOWED_USER_IDS`: comma-separated UUIDs of approved test recipients.

An empty allowlist blocks all test push, including broadcasts and call alerts.
Production notification behaviour is unchanged. Never use a production-wide
recipient list or print credential values. Changing these settings needs a test
backend recreation; it does not need a new iOS build.
