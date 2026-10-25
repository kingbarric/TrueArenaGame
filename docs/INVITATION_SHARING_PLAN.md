# Shared invitations: Huuds and championships

Status: implemented locally on `codex/local-bot-gameplay`. Not deployed.

## Intended flow

1. Share a branded image and clickable invitation through the system share sheet.
2. Installed app: open the exact invitation, show its details and accept it.
3. App missing: show a branded invitation/install page, detect the device, and
   offer its published store link. Both listings are currently in review, so
   absent store URLs must show an honest unavailable state.
4. Google Play can carry the invitation via Install Referrer. Explicitly copying
   the invitation before installing supports the iPhone/preview APK path; opening
   the original invitation again is always available. No browser gameplay.
5. Retain the destination across guest entry, registration, and process restart.
   Accept as a guest, or register; registration is optional for playing.
6. Huud invitations keep the Huud's approval/block/removal rules. Championship
   links grant entry to that specific live championship when explicitly accepted;
   they cannot enter another or expired championship. Agents remain excluded.

## Implementation

- One validated invitation model and durable pending destination for both kinds.
- Native share artwork reuses the real PlayHuud and game logos, with compelling
  game-specific invitation text and a readable invitation URL/code.
- Public server-rendered pages include Open Graph/Twitter metadata so crawlers
  see the correct title and game image without executing JavaScript.
- App links cover both invitation paths on iOS and Android. Pending invitations
  return after sign-in/guest onboarding instead of falling onto the game catalogue.
- A championship acceptance endpoint validates the code, current competition,
  capacity, human identity, blocks/removals and Huud activity before registration.
- Guest audit covers all room game types and SlayHuud participation. Hosting,
  purchases, competitive public voting and account-only social features retain
  their separate policies.

## Validation

Test parsing, malformed/foreign links, saved invitation recovery, both guest and
account handoff, expired/full competitions, private Huud access, blocked/removed
people, duplicate acceptance, bot exclusion, share image rendering and HTML
escaping. Render and inspect the exported artwork. Store-to-app installation
requires published store listings and physical first-install verification.

## Verified implementation

- Full backend `verify -DskipITs`: 923 tests across 137 suites, zero failures
  or errors; seven environment-dependent checks skipped (six native engine
  checks and one live-storage check). Docker integration tests were excluded.
- 110 Flutter regression tests passed, plus the artwork export test. Ten
  offline website tests cover device/store routing, encoded Play referrers,
  clipboard refusal, unpublished listings and both app-link associations.
- New invitation components pass static analysis without issues. Android's
  debug APK compiles with Install Referrer 2.2. Generated 1200×630 social
  covers and portrait native share cards were rendered and visually inspected.
- Guest join is tested across all nine room game types. SlayHuud now permits
  human guest participation; guest matches stay unrated. Hosting and public
  competitive voting retain their registered-account requirements.
- Saved invitations survive actual `AppState.bootstrap`, guest entry and
  registration selection. Accepting as a guest is tested through the precise
  invitation API and into the requested competition.
- Evidence is in `output/invitation-validation/verification.json`, with the
  exported portrait previews beside it. Public cover images are in
  `website/assets/invite-*.png`.

## Release configuration

The listings are currently in review. Set these only to the actual published
listing URLs when available; they are passed through each Compose environment:

- `PLAYHUUD_IOS_STORE_URL`: the HTTPS `apps.apple.com` listing.
- `PLAYHUUD_ANDROID_STORE_URL`: the HTTPS `play.google.com` listing.

The public page endpoints, Caddy routing, website assets and app update must be
released together. Both `/huud/*` and `/championships/*` are included in iOS's
association file and Android's app-link manifest. Confirm Android's association
fingerprint matches the Play App Signing certificate when publishing.

Google Play carries the invitation in its install referrer. iPhone installs use
explicit copying before the App Store; iOS may request paste permission on first
launch. Returning to the original invitation and tapping Open is the reliable
fallback. A normal store URL alone does not promise automatic iPhone handoff.
Physical store-to-app testing remains pending the published listings. There is
no browser gameplay.

References: [Google Install Referrer](https://developer.android.com/google/play/installreferrer/library),
[Apple universal links](https://developer.apple.com/documentation/xcode/allowing-apps-and-websites-to-link-to-your-content).

## Isolated phone testing

`PLAYHUUD_PUBLIC_INVITE_BASE` configures backend invitation links, metadata and
cover URLs. It defaults to `https://playhuud.com`; the isolated test deployment
uses `https://vps-8030ec94.vps.ovh.net/test`. Covers are bundled with the backend
and publicly served through `/api/v1/invitations/covers/invite-{game}.png`.
The phone build sets `INVITE_BASE_URL` to that same test base. Parsing still
accepts production links and accepts only the explicitly configured test host
and prefix. Both Huud and championship shares stay on their own database.

The test host is not an iOS associated domain: its invitation page's **Open
invitation in PlayHuud** button opens the installed app via its custom scheme.
Production association files and store-release verification remain separate.
