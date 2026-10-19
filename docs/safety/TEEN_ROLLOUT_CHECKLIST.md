# Teen rollout acceptance checks

Status: blocked from activation; `AGE_ENFORCEMENT_ENABLED=false`.

## Communication and privacy

- [ ] Create a single server policy used by friend requests/acceptance, existing conversations, game invitations/nudges, groups, Huuds, championship invites, public previews, voice-session join/tokens and notification delivery.
- [ ] Unknown age receives protected treatment; bot exemptions cannot be used as human identities. Do not trust a client-supplied age or `teen=false` field outside the authenticated declaration/assurance service.
- [ ] Restrict adult-to-teen contact in both directions. Existing friendships and rooms must not silently bypass it. Decide and document any guardian-approved exceptions before implementing them.
- [ ] Teen communication initially only with accepted, eligible friends; no public stranger invitations, public voice sessions or mixed-age room membership. Re-evaluate eligibility when membership changes.
- [ ] Audit encrypted DM reporting and blocked users in already-open conversations. Do not remove encryption under the guise of moderation.
- [ ] Make teen profiles private by default and suppress nonessential identity/location on search, contacts, friends-of-friends, rankings, feed recommendations and previews. Cover historical records and account age corrections.
- [ ] On restriction/block/consent revocation, stop WebSocket delivery, pending pushes and active LiveKit participation, not just future HTTP requests.

## Age and regional consent

- [ ] Review minimum ages, age-assurance and consent rules per supported region with the responsible operator. Default unsupported/unknown decisions to restricted access.
- [ ] Add Apple's Declared Age Range bridge with availability handling. Test declined sharing, unavailable APIs, older devices, region-specific required features and guardian consent revocation.
- [ ] Define equivalent Android age assurance and consistent server enforcement. A locally modified app must not defeat the policy.
- [ ] Define a reviewed age/country correction flow and appropriate retention; users must not gain adult privileges by editing a dropdown.
- [ ] Handle existing guests, upgraded guests, new devices, account deletion/recreation and linked accounts. Document residual self-declaration bypass risk.
- [ ] Do not treat a privacy acknowledgement, parent's email address or a checkbox as verified parental consent.

## Moderation and operations

- [ ] Test and operate filtering for public posts, names, Huud chat and uploaded images; retain reporting/blocking for permitted content and appeals.
- [ ] Establish voice safety, moderator controls, encrypted-content report evidence, escalation, urgent-child-safety handling and measurable response ownership.
- [ ] Approve DPIA/children's risk assessment as applicable, age-appropriate privacy/terms/community rules and data minimisation. Source code cannot establish that these operational duties are performed.

## Test matrix and deployment

- [ ] Unknown, under-13, 13–15, 16–17 and adult accounts; adults claiming a younger age; bots; deleted accounts.
- [ ] Teen↔teen friend/stranger and teen↔adult friend/stranger interactions, plus blocked/unfriended and pending-request pairs.
- [ ] Room invitation codes, public previews, feed/watch paths, championships, voice joins, cached credentials, reconnects and push/deep-link entry.
- [ ] Race: block/age restriction while a message, invitation, room join or media token is being issued.
- [ ] Accessibility, narrow devices, guest sign-in, provider sign-in, offline/retry, switching accounts and deletion from a restricted gate.
- [ ] Drain/revoke existing active media sessions and migrate historical discoverability before activation. Verify rollback does not reopen restricted accounts.
- [ ] Prepare truthful store questionnaire answers, reviewer instructions and privacy declarations. Obtain authorization separately before replacing the submitted Apple build or changing the store rating.
