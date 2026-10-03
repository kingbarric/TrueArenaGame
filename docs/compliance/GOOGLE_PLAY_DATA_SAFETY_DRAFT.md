# PlayHuud — Google Play Data Safety & submission notes (draft)

**Status:** Draft reference for filling in Play Console's own forms by hand. Nothing has been submitted or published. This is not a substitute for reading what Play Console actually asks at the time of filing — its forms change over time.

## Build

- Package: `app.truearena.truearena` (confirm this matches the app already created in Play Console).
- First release target: **Internal testing** track.
- Signed release App Bundle built 2 October 2026: `app/build/app/outputs/bundle/release/app-release.aab` (102.6 MB), signed with the existing `app/android/app/playhuud-release.keystore.jks` via `app/android/key.properties` — the same signing setup already used for the direct-download APK.
- `versionCode`/`versionName` come from `app/pubspec.yaml`'s `version: 1.0.0+1` → versionCode `1`. Fine for a first upload; each subsequent upload to any track needs a higher versionCode.
- `targetSdk`/`compileSdk` = 36 (Flutter 3.47.3's default) — comfortably meets Play's current target-API-level requirement for new uploads.
- Minor, non-blocking: the local Android SDK is missing `cmdline-tools`, so this build's native library debug symbols weren't stripped. Play Console may suggest uploading a separate debug symbols file for readable native crash reports later; it won't block the upload.

## Data Safety form — suggested answers

Source for all of this: a repo-wide audit on 2 October 2026 citing exact file:line locations (ask to see them again if needed before filing).

| Data type | Collected? | Shared with third parties? | Why | Notes |
| --- | --- | --- | --- | --- |
| Name | Yes | No | Account functionality | Display name / username you set, or provided by Google/Apple sign-in. |
| Email address | Yes | No | Account functionality, account recovery | Only if you sign in with Google/Apple or verify an email. |
| Phone number | Yes | No | Account functionality, friend-finding | Only if you verify a phone number. Also see "Contacts" below. |
| User IDs | Yes | No | App functionality | Internal account ID, device ID for guest sessions. |
| Contacts | Yes (optional feature) | No | App functionality (find friends) | Phone numbers from the device address book are sent to the server once, on demand, to check for matches. Contact **names** are never sent. The submitted number list is not stored after the check completes — no persistence call exists in `FriendService`/`FriendController` (`backend/ta-api/src/main/java/app/truearena/api/friends/`). Sent over TLS, not hashed before transmission — don't describe this as "hashed matching." |
| Messages (in-app messages) | Yes | No | App functionality | Server stores whatever the client sends in `messages.text`. 1:1 DMs are end-to-end encrypted *after* both sides exchange keys (server sees only ciphertext then). Group messages, and DMs before key exchange, are stored as plaintext server-side — there is no server-side encryption layer at all; "encrypted in transit" (TLS) is true for all of it, "end-to-end encrypted" is only true for the DM-after-key-exchange case. Don't claim universal E2E in the form. |
| Audio (voice calls) | Yes | No | App functionality | Calls run on a self-hosted LiveKit server (TrueArena's own infrastructure/domain — see `infra/docker-compose.prod.yml`, `infra/livekit.prod.yaml`), not a third-party calling vendor, so this is not "shared with a third party" in Play's sense. 1:1 calls get an extra end-to-end encryption layer; group calls use standard DTLS-SRTP transport encryption only. |
| Audio (microphone, Word Bluff) | **No** | No | — | Speech recognition runs entirely through the OS's on-device recognizer (`speech_to_text` plugin). Audio and transcribed text never leave the device; only a boolean correct/incorrect gameplay signal is sent. You can likely answer "not collected" for this specific use, though the app does hold the RECORD_AUDIO permission for it. |
| Photos/videos | Possibly | No | App functionality | Only if a user picks a custom avatar image via the image picker — confirm current avatar-upload behavior before answering if this matters to you. |
| App activity / in-app purchase or financial info | **No** | — | — | Coins are earned-only — no real-money purchase, no cash-out, no payment processor anywhere in the app or backend (`CoinService.java`'s own design doc states this explicitly). Don't declare "purchase history" or "financial info" data types — there's nothing to collect. |
| Device or other IDs | Yes | No | App functionality, guest accounts | Device model/OS version; a generated device ID for guest sessions. |
| Analytics / advertising ID | **No** | — | — | Confirmed no analytics, crash-reporting, or ad SDK anywhere in `pubspec.yaml`/`pubspec.lock`, direct or transitive. |

**Data deletion:** Play Console will ask whether users can request account/data deletion. We can truthfully say yes if you're willing to act on deletion requests sent to the contact email — there's no in-app self-serve delete flow found in the code, so this would be a manual process on your end for now.

**Open item — don't answer this from assumption:** `docs/DEV_REFERENCE.md` describes unverified guest accounts as getting "one game" and then clearing, but the audit found no corresponding server-side deletion/expiry job in `backend/`. The privacy policy page I drafted (`website/privacy/index.html`) deliberately does **not** promise automatic deletion of guest data, to avoid stating something the code doesn't actually do. If there's a cron/ops job doing this outside the repo, let me know and I'll tighten the wording; otherwise this is worth fixing before relying on it as a privacy claim anywhere official.

## Content rating questionnaire (IARC) — heads up

Play Console's content rating questionnaire asks directly about gambling/wagering mechanics. Answer based on what's actually true: players can optionally wager the in-game coin currency on match outcomes ("winner takes the pot"), but coins have no real-world purchase path and no cash-out — there is no real-money gambling. Depending on how IARC's questionnaire is worded this year, this combination (virtual-currency wagering, no purchase, no cash-out) usually avoids the "simulated gambling" / real-money-gambling classification, but may still affect the age rating band (e.g. pushing from "Everyone" up a tier) purely for the wagering mechanic itself — answer the questionnaire's exact wording honestly rather than assuming a rating in advance.

## Permissions

- `INTERNET`, `RECORD_AUDIO`, `READ_CONTACTS` are declared in `app/android/app/src/main/AndroidManifest.xml`, each already commented in-repo with the feature that needs it.
- `READ_CONTACTS` is a sensitive permission but — as I understand Play's current policy — isn't one of the ones requiring the special "Permissions and APIs that Access Sensitive Information" declaration form in Play Console (that form targets things like SMS/Call Log or Accessibility Service access); "find friends from contacts" is a long-standing, commonly approved use case. Still, double-check Play Console's own Permissions section when you get there, since policy specifics move over time and I can't see the live console.
- The app already does the right thing functionally: contacts access is requested on-demand at the point of use, not at launch, and only phone numbers (not full contact records) are transmitted.

## Privacy policy

Drafted at `website/privacy/index.html`, linked from the homepage footer (`website/index.html`). **Not deployed to the live playhuud.com yet** — same as the Android APK, publishing website changes to the production server appears to be a separate manual/deploy step, not just a repo commit. Review the page, then have it pushed live before entering its URL in Play Console (and in App Store Connect, which will likely want the same URL eventually).
