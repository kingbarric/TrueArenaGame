# Main integration and phone delivery — 27 October 2026

## Preservation and integration

The user requested that all branches be brought into main before rebuilding the phone, with no lost work.

- Updated local main from origin/main at 806a9ea, then included the six newer app/invitation/Draughts commits through 8439152.
- Merged auth fix a2fdafb and its verification notes through codex/fix-auth-session.
- Merged codex/auth-test-deploy history; retained the newer delivery notes.
- Reconciled the nine older Huud lifecycle commits. Seven were patch-equivalent already; the remaining two (3bd481c/7406767 and e1731de/de02bd2) had identical changed lines despite differing context. Kept current implementations, including the Traitors table/reveal, five-Huud support and Moments feed.
- Preserved codex/social-huud-v1 via a history-only merge. This separate, superseded prototype uses huud_sessions and a V38 migration, while the current app uses huud_spaces and subsequent migrations. Its code remains fully recoverable in history; it was not reactivated or allowed to overwrite current lifecycle, auth or schema behavior.
- Verified every local and origin branch tip is an ancestor of main (64 branch refs).

Original worktrees and branches were retained. Uncommitted account-deletion draft code and other untracked source/documents remain in their original worktrees and were separately backed up, not activated as unfinished app functionality. Generated outputs/caches remain untouched in their original worktrees.

A verified full Git bundle and copies of uncommitted source/documents are saved outside the worktrees at:
`/Users/ericbarima/Documents/projects/TrueArena/output/main-integration-20261027/`.

## Branch tips at audit

```text
codex/android-release-prep e20a8f7
codex/apple-production-release ab061c3
codex/apple-resubmission-20261027 8439152
codex/auth-test-deploy 62a5dfa
codex/bots-phone-integration 1ff71d5
codex/fix-auth-session 889e624
codex/huud-custom-icons 7406767
codex/huud-discovery-members 0b5d2a4
codex/huud-game-entry 8bcdbde
codex/huud-game-lifecycle 2a38bfb
codex/huud-icons-phone 3bd481c
codex/live-feed-main ab061c3
codex/live-feed-polish 1fc4036
codex/local-bot-gameplay 2ab38da
codex/ludo-mic-approval 0a0e421
codex/monopoly-classic-depth 4df2384
codex/monopoly-recovery 78bce10
codex/production-invitations-release f53f615
codex/remove-coin-wagering d262c21
codex/slayhuud 6060ae3
codex/social-huud-v1 e20eb96
codex/teen-safety ecd5c01
feature/account-deletion 74f287d
feature/chess-agent 0153937
feature/chess-engine 0d5a8be
feature/home-layout f463b44
feature/home-profile-calls 44b7051
feature/huud-championship-64 d9c5792
feature/huud-feed d6f666e
feature/huud-session 0c4dbee
feature/live-moments 54ed5af
feature/multi-huud 362503f
feature/player-cards-traitors-audit e0d1294
feature/slayhuud-shipping 1d2dfec
feature/start-needs-players f5bd327
feature/traitors-host-clock 7f86cbb
feature/traitors-mode-art ab315c5
feature/traitors-spectators 806a9ea
feature/voice-pause ece1faf
feature/ws-game-transport 26e9ca5
main d82105a
merge/release-into-main 4656e23
merge/traitors-host-clock 1ff71d5
release 74f287d
worktree-whot-friends-fixes 6bd5f2c
origin d82b0e8
origin/codex/apple-production-release a8238ad
origin/codex/huud-icons-phone 3bd481c
origin/codex/monopoly-classic-depth 4df2384
origin/codex/monopoly-recovery 78bce10
origin/codex/production-invitations-release f53f615
origin/codex/remove-coin-wagering d262c21
origin/codex/slayhuud 6060ae3
origin/codex/social-huud-v1 e20eb96
origin/feature/huud-championship-64 d9c5792
origin/feature/huud-session 9915652
origin/feature/multi-huud 362503f
origin/feature/player-cards-traitors-audit e0d1294
origin/feature/slayhuud-shipping 5a91ca3
origin/feature/start-needs-players f5bd327
origin/feature/traitors-mode-art ab315c5
origin/feature/traitors-spectators 806a9ea
origin/feature/ws-game-transport d82b0e8
origin/main 806a9ea
origin/release eca4be6
```
