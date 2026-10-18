# Android release preparation — 18 October 2026

## Completed

Eight real phone screenshots, the 512×512 PlayHuud icon and 1024×500 feature graphic are saved in the Google Play Console listing draft. No Google release/review was submitted. Local assets, capture provenance and proof are under `output/google-play/` in the primary workspace; these output files are not included in Git.

The privacy policy URL is configured as `https://playhuud.com/privacy/`. The user selected **teens and adults (13+)** for Google Play. Policy wording permits stricter store/region restrictions. Sign in details are saved using the approved dedicated reviewer account. Audience groups 13–15, 16–17 and 18+ are saved. Regional content ratings may impose higher ages.

The client now waits for an authoritative game snapshot before navigating from the resume lobby. A legacy room marked in_game but lacking a live runtime displays retry and return controls instead of an empty board. This does not reconstruct a lost casual match. Restart persistence for those matches remains a separate limitation.

Validation: ten focused socket/resume/recovery tests pass; analysis of the changed lobby and recovery tests reports no issues. The new tests cover a phase arriving before its board, a successful snapshot handoff, and retry/exit when the server cannot restore a match.

Signed iOS test-profile build **2026101801** installed on iKingbarric using `https://vps-8030ec94.vps.ovh.net/test`. Automatic launch was blocked because the phone was locked. Signed Android **1.0.1 (6)** app bundle built against production (133.9 MB); it has not been uploaded or submitted to a track.

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

The existing Alpha draft is **1.0.1 (5)**, with 178 countries/regions and a tester list already configured. Uploading the signed build 6 through the browser twice failed with “Couldn’t upload. Try again.”; no replacement was saved and no release was submitted. Build 6 remains local, signature-verified, SHA-256 `44fbdcdf4d86d5820f3bd91ad0bd7e4a647b4b9f562a3bc88e47691504e5d3a4`. The extension’s file URL access was requested for upload troubleshooting. Do not confirm/roll out the old draft while intending to ship build 6.

The App content overview now says “You’re all caught up.” The dashboard shows only closed-test rollout/production-access tasks, with zero opted-in testers. Proof: `output/google-play/app-content-complete.jpg`, `iarc-ratings-saved.jpg`, and `setup-complete-dashboard.jpg` in the primary workspace.

## Remaining

- Upload build 6, replace build 5 in the Alpha draft, and inspect the final preview before release authorization.

- Perform the final end-to-end reviewer/account deletion smoke check against the deployed backend before submission; do not delete the reusable reviewer account.
- Recheck the final Android artifact and run live game/connection smoke checks.
- Closed testing must have at least 12 opted-in testers for 14 days before applying for production access. The live Console showed zero opted in during this check.
