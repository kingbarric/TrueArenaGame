# Android release preparation — 18 October 2026

## Completed

Eight real phone screenshots, the 512×512 PlayHuud icon and 1024×500 feature graphic are saved in the Google Play Console listing draft. No Google release/review was submitted. Local assets, capture provenance and proof are under `output/google-play/` in the primary workspace; these output files are not included in Git.

The privacy policy URL is configured as `https://playhuud.com/privacy/`. The user selected **teens and adults (13+)** for Google Play. Policy wording permits stricter store/region restrictions. Sign in details are saved using the approved dedicated reviewer account. Audience groups 13–15, 16–17 and 18+ are saved. Regional content ratings may impose higher ages.

The client now waits for an authoritative game snapshot before navigating from the resume lobby. A legacy room marked in_game but lacking a live runtime displays retry and return controls instead of an empty board. This does not reconstruct a lost casual match. Restart persistence for those matches remains a separate limitation.

Validation: ten focused socket/resume/recovery tests pass; analysis of the changed lobby and recovery tests reports no issues. The new tests cover a phase arriving before its board, a successful snapshot handoff, and retry/exit when the server cannot restore a match.

Signed iOS test-profile build **2026101801** installed on iKingbarric using `https://vps-8030ec94.vps.ovh.net/test`. Automatic launch was blocked because the phone was locked. Signed Android **1.0.1 (6)** app bundle built against production (133.9 MB), uploaded to the Alpha closed-test release and saved pending review. No review or rollout was submitted.

## Console forms completed

Saved privacy, reviewer access, audience, Data safety, Advertising ID (No), government (No), financial features (None), health features (None), and Game → Casual category. The setup prerequisite checklist no longer appears on the dashboard. Eight genuine screenshots remain unlabelled; only the generated icon/feature graphic are labelled AI-generated. No release was sent for review.

IARC terms were accepted with explicit user approval and the official questionnaire saved. Declared Traitors’ referred/implied human violence without gore, rare scary imagery, frequent revealing fashion outfits in a non-erotic fashion context, virtual-currency entry/rewards, user interaction, block/report controls and private invited play. No active chat moderation is claimed. A cosmetic theme name alone was not treated as alcohol content. No real-money gambling, purchases, cash-out, precise-location sharing, sexual acts or displayed nudity were declared.

| Region | Generated rating |
| --- | --- |
| North America | ESRB Teen |
| Europe | PEGI 7 |
| Germany | USK 12+ |
| Brazil | 12+ |
| South Korea | 15+ |
| Taiwan | Parental Guidance 15 |
| Saudi Arabia | 16 |
| Australia | Restricted 18+ — Simulated Gambling; Online Interactivity and Chat |
| Rest of world / Russia | 7+ |

These are the saved questionnaire results, subject to authority/Google review. The chosen 13+ target audience does not override higher regional ratings. Australia’s result follows the questionnaire’s earned-token entry/reward response; do not omit the mechanic to obtain a lower rating.

The public privacy age wording and outside-app deletion page are live. Source and support wording are committed. See GOOGLE_PLAY_DATA_SAFETY_DRAFT.md for the current saved declarations; the old October 2 assumptions are superseded.

## Closed-test draft

The Alpha closed-test release is now **1.0.1 (6)**, with the existing 178 countries/regions and tester list unchanged. The user enabled Chrome extension file access and restarted the browser. Automated file selection still failed before transferring bytes; Chrome’s native file picker successfully uploaded the same signature-verified bundle. SHA-256: `44fbdcdf4d86d5820f3bd91ad0bd7e4a647b4b9f562a3bc88e47691504e5d3a4`.

Build 5 was removed only from this release and remains recoverable from the artifact library. Build 6 is the sole included bundle. Updated release notes mention Huud improvements, account deletion, Huudpoly branding and unavailable-match recovery. Google’s preview reported **Ready to release**, with no blocking errors and a 61.6 MB estimated new-install download. Preview confirmation was saved to Publishing overview; no Send for review or rollout action was taken. Proof: `output/google-play/build-6-ready.jpg` in the primary workspace.

The App content overview now says “You’re all caught up.” The dashboard shows only closed-test rollout/production-access tasks, with zero opted-in testers. Proof: `output/google-play/app-content-complete.jpg`, `iarc-ratings-saved.jpg`, and `setup-complete-dashboard.jpg` in the primary workspace.

## Final checks and backend blockers

Fresh reviewer login passed against production and through the signed Android build. The existing code was recovered privately from the original server configuration without rotation; the temporary local credential file was removed. Profile, friends and account-deletion requirements returned 200. A new disposable production guest required explicit deletion confirmation, returned 204 on confirmed deletion, then rejected both access and refresh tokens with 401. The reviewer account was retained.

The new-game check found that AccountSessionGuard rejected bot identities in game-room WebSockets. The fix adds a room-only existence check after JWT and membership authentication; ordinary HTTP/inbox checks still reject bots and deleted users. It also replaces push-token read-then-save with a single PostgreSQL token upsert after a real concurrent registration error was observed.

Backend fix revision: `0fa90024f7aa04c1f2f506b7eee648015ecc2c87`. Full backend suite: 777 tests, zero failures/errors, one optional check skipped. The isolated test backend is healthy on this revision. Live test checks passed: 24 concurrent push-token registrations, account switching, deletion confirmation/token invalidation, and an authenticated Chess bot playing two moves before the private zero-stakes match finished.

Reusable checks: `backend/dev-tools/release-account-smoke.py` and `backend/dev-tools/release-bot-smoke.mjs`. They do not print credentials/tokens or send notifications. Production rollout of the backend fix awaits the user's restart decision because recent player activity is linked to two existing game records. No Android rebuild is needed for these backend-only changes.

Google's quick checks passed and Publishing overview contains the Alpha build 6 release and saved store/content declarations (15 changes). Closed-test submission will follow the backend fix and final live check. No production-store rollout is authorized by this step.

## Remaining

- Apply the tested backend fixes after the production restart decision, verify the live bot flow and submit the Alpha package for closed-testing review.
- Closed testing must have at least 12 opted-in testers for 14 days before applying for production access. The live Console showed zero opted in during this check.
