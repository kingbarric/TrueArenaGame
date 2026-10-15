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
Invite uses an opaque cream surface, dark icon and label, outlined edge and small
raised shadow so it remains distinct from the orange card in either theme.

“Away” describes presence in the live Huud, not whether the person's phone has
internet. The app sends a heartbeat every 45 seconds; the member response requires
activity within the last 75 seconds, an active live seat, and a foreground app.
Connected game, inbox and voice activity also refreshes the activity record.
The room refreshes its member data every eight seconds.

The room automatically retries renderer failures with bounded backoff, recreates
a failed WebView, detects stalled loads, and resumes retries when the app returns
to the foreground. Retry timers stop when the screen is disposed. API requests
and token refreshes time out after 30 seconds rather than hanging indefinitely.


## Listen before joining

The full-screen, swipeable Live Huud preview automatically plays the visible
Huud's conversation. The sound control mutes/unmutes listening; it never opens a
microphone. Swiping, covering/closing the preview, or backgrounding the app stops
that connection. Returning resumes listening. Existing friend calls are preserved;
preview audio waits until the call ends. A previous Huud's voice connection is
released before browsing a different Huud.

`POST /huud-spaces/{id}/listen` applies the same live, privacy, membership,
approval, removal and block checks as watching. The credential is short-lived and
cannot publish media or data. A separate identity and unique visit ID prevent
previewing from taking a live seat or a stale swipe from disconnecting a newer
visit. `DELETE /huud-spaces/{id}/listen/{previewId}` stops only that visit. Viewer
counts use the existing 60-second watch heartbeat lease.

Opening a preview now uses `/watch` even for existing members; it does not walk
them into the live hangout. Joining switches to the normal Huud voice flow.
Ending Live, changing privacy or blocking/removing someone disconnects applicable
preview listeners. The expiry sweep also removes stale or no-longer-authorized
listeners. Transient client failures reconnect with bounded backoff.

Validation: 57 Flutter tests, 40 Huud integration tests, 13 lifecycle integration
tests and the signed-token permission/expiry tests passed. A generated test tone
through the isolated test voice service reached the receive-only client (148
non-silent audio frames); server permissions confirmed media/data publishing was
disabled. The unique temporary room was removed. Physical phone speaker output
with another person talking still needs an on-device check.

## Main menu visibility

The default dark theme uses a light orange bottom navigation surface, dark
labels, full-opacity idle artwork and a stronger orange selected-tab highlight without an
orange glow. Other visual themes keep their existing navigation treatment.
The native dark-theme shell was checked on the Huud and Profile tabs; all 12
existing theme/navigation checks passed and the edited files analyze cleanly.
For a local shell preview, add `HUUD_SHELL_PREVIEW=true` and
`HUUD_DARK_PREVIEW=true` to the `huud_preview.dart` run defines.

Join buttons in the Huud code card, shared feed cards and full-screen live preview
also use light orange with dark text and an outlined edge, separating the action
from the stronger orange surrounding it. The final revision passed 81 existing
navigation and Huud tests; analysis found no errors or warnings (two existing
advisory notes remain in the feed/swipe screens).
