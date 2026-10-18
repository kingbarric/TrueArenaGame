# Android release preparation — 18 October 2026

## Completed

Eight real phone screenshots, the 512×512 PlayHuud icon and 1024×500 feature graphic are saved in the Google Play Console listing draft. No Google release/review was submitted. Local assets, capture provenance and proof are under `output/google-play/` in the primary workspace; these output files are not included in Git.

The privacy policy URL is configured as `https://playhuud.com/privacy/`. The user selected **teens and adults (13+)** for Google Play. Policy wording permits stricter store/region restrictions. Audience configuration still depends on completing Google's Sign in details form; explicit approval to transmit the dedicated reviewer credentials was requested.

The client now waits for an authoritative game snapshot before navigating from the resume lobby. A legacy room marked in_game but lacking a live runtime displays retry and return controls instead of an empty board. This does not reconstruct a lost casual match. Restart persistence for those matches remains a separate limitation.

Validation: ten focused socket/resume/recovery tests pass; analysis of the changed lobby and recovery tests reports no issues. The new tests cover a phase arriving before its board, a successful snapshot handoff, and retry/exit when the server cannot restore a match.

Signed iOS test-profile build **2026101801** installed on iKingbarric using `https://vps-8030ec94.vps.ovh.net/test`. Automatic launch was blocked because the phone was locked. Signed Android **1.0.1 (6)** app bundle built against production (133.9 MB); it has not been uploaded or submitted to a track.

## Remaining

- Finish Sign in details, then set audience age groups 13–15, 16–17 and 18+.
- Complete Data safety, content rating, government/health/financial declarations and store settings using current Console questions and actual app behavior.
- Verify account deletion against the final deployed backend and publish matching support/privacy instructions before submission.
- Recheck the final Android artifact and run live game/connection smoke checks.
- Closed testing must have at least 12 opted-in testers for 14 days before applying for production access. The live Console showed zero opted in during this check.
