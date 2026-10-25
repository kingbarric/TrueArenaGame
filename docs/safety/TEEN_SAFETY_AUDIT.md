# Teen safety audit and implementation status

Audited `origin/main` at `8dbb810` on 19 October 2026. This branch is an isolated development increment; no production deployment, store-rating change, or modification to the Apple submission is authorized by this document.

## Existing on main

| Area | Evidence | Limits |
| --- | --- | --- |
| User reporting | `SafetyService.report`, `SafetyController`, `huudspace/safety_sheet.dart` | Reports can retain reported Huud message/feed text; this is not a general moderation filter or evidence that reports are handled within a defined response time. |
| Blocking | `SafetyService.block` removes friendships/requests, removes a blocked participant from the blocker's hosted Huud, stops previews | Existing DM participants are checked by conversation membership rather than current friendship on every send. Audit existing-thread delivery, groups, calls and race conditions before treating blocking as comprehensive. |
| DMs require a friend initially | `ChatService.openDmWithPerson` checks accepted friendship | There is no age distinction. `requireParticipant` accepts an existing DM participant without checking current friendship/block status. |
| Voice controls | `VoiceSessionService`, `CallService`, Huud mic request controls | No age-based adult/minor restriction or parental permission flow found. Live media credentials need independent revocation/leave behaviour on restriction. |
| Discoverability controls | `CompetitiveProfileService`, `HuudPreviewService`, `HuudSpaceService` | Competitive profiles default public when a profile row is absent. Search/contact matching, feeds, rankings, previews and public invitations are not teen-specific. |
| Account deletion | `AccountDeletionService`, `DeleteAccountScreen` | Supports guests; Apple token revocation is implemented. This is not age assurance. |
| Support and privacy | `website/support`, `website/privacy`, public support email | Main's privacy page says 13+ and explicitly does not claim verification. A store label does not enforce this. |
| Reports administration | `AdminReportsController`, `AdminKeyFilter`, internal reports page | Report review/removal tooling exists. No staffed response-time commitment, child-safety escalation procedure or training was verified from source. |
| Moderation | Reporting, removal controls and Huud chat rate limiting | No comprehensive pre-publication text/image/voice filtering found. DMs use client encryption: server-side plaintext filtering would not inspect them. |

## Implemented in this branch

- Private age bands (`UNDER_13`, `AGE_13_15`, `AGE_16_17`, `ADULT`) and an ISO country declaration. No birth date, ID document or public age field.
- Self-only authenticated read/write endpoint, immutable first declaration, concurrent-write protection via the primary key and `ON CONFLICT DO NOTHING`, and account-deletion cascade.
- The server records `self_declared`, timestamp and notice version. Acknowledging the privacy notice is explicitly **not parental consent** or verified age/location.
- A normal country selector, neutral age-range choices and an Age and privacy screen available to accounts and guests.
- A rollout switch `AGE_ENFORCEMENT_ENABLED`, default **false**. When enabled, unknown and minor age bands are refused normal authenticated API and WebSocket access. Bots remain eligible only through existing room-token/membership checks.
- Narrow exceptions preserve age declaration, own account access/deletion, and report/block recovery. Client retry failures do not unlock content, and resumed games/incoming-call overlays are not mounted while the client gate is closed.
- Teen access is a launch interlock, **not a configurable true flag**. It remains false and the current enforced minimum remains 18 in this increment. Country selection does not manufacture a regional legal decision.
- Draft policy text explains the added collection. It is not published by creating this branch.

## Not implemented / not enabled

This is the age-and-access foundation, **not the completed teen experience**. It does not yet supply:

1. Private-by-default teen discovery across profiles, contacts, leaderboard identity, feed distribution and public previews.
2. Age-aware friendship requests, existing-DM checks, group membership, invitations and server-push recipient filtering.
3. Friends-only teen voice/game rooms with every participant checked; prevention of mixed adult/minor rooms and stranger invitations, including join codes, deep links and old clients.
4. Apple Declared Age Range integration, regulatory-feature handling, parental consent/revocation or significant-update permissions. The app must not label its self-declaration as an Apple-verified result.
5. A reviewed, versioned regional age/consent policy. Language, IP geolocation and a declared country are not sufficient assurances by themselves.
6. Comprehensive moderation for public content, voice and images, encrypted-message reporting, abuse escalation and measurable report response handling.
7. Legal/operational approval of children's privacy/risk assessments and revised terms/community standards.

Existing accounts that declare a minor age may already have public historical content and active media sessions. Enabling enforcement alone does not retrospectively hide all historical appearances or revoke existing LiveKit credentials. Deployment must keep the switch off until migration/cleanup and media-revocation behaviour are implemented and tested. This is a rollout blocker, not a claim of completed protection.

## Sources for the subsequent implementation

- Apple age rating procedure: https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating
- Apple age assurance: https://developer.apple.com/support/age-assurance
- Apple UGC requirements: https://developer.apple.com/app-store/review/guidelines/#user-generated-content
- UK Children's Code: https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/childrens-information/childrens-code-guidance-and-resources/age-appropriate-design-a-code-of-practice-for-online-services/code-standards/
- Ofcom children's protection guidance: https://www.ofcom.org.uk/online-safety/protecting-children/check-how-to-comply-with-the-protection-of-children-rules?language=en

These references inform the work; they do not certify legal compliance.
