# Huud 3D room

First phone delivery: 1.0.1 (2026101401), commit a1b0e272298a15c1edae0e6c69d640e34262645a, test API. Installation and launch confirmed with CoreDevice; the installed bundle version was read back from the phone. Renderer HTML and compiled test API were checked in the signed app. Test catalogue v34 is healthy; revised male assets were uploaded additively to Cloudflare R2.

People opens first, followed by Game and Chat. People and Chat each have a bounded inner scroll view. Profile, friend, gift, membership, voice permissions, unread messages, games and championships retain their existing flows. The first version uses seated avatars at a round table, head-level names, and speaking indications from actual LiveKit participant state. Simulator fixture indicators are explicitly debug-only.

The second version replaces the table seating with couches in a furnished sitting room, titled The Huud. Each room accommodates eight couch seats and four standing people; additional rooms remain reachable through paging. Sit, Stand and Walk affect your own avatar. Walking follows a bounded path around a low coffee table. Names follow head bones while moving. Reduced motion suppresses idle and walking animations. Geometry and textures are shared between instances; skeletons and tinted materials remain independent.

Avatar posture is sent on the existing Huud LiveKit data channel. It accepts only sit, stand or walk, applies the authenticated sender identity rather than a payload user ID, caps incoming packet size and ignores unrelated topics. Peers request current states when they join; movement stays usable locally if voice is unavailable. Remote clients animate the selected posture locally, rather than exchanging precise world coordinates. Exact multi-device path synchronization is outside this version.

Avatars currently use stable default body, hair, skin and outfit variations by account identity. They are not reconstructed from profile photographs or linked to a user's SlayHuud look selection.

Validation: 64 passing Huud tests and 90 passing renderer tests; no analyzer diagnostics in the new movement and canvas code. Coverage includes Huud widget regressions, bounded-panel and larger-group tests, movement-state tests, and source-model seating, independent-skeleton, overflow-spacing and walking-path checks. Existing renderer asset tests passed before the sitting-room changes. Final simulator visual review and a live two-phone movement check must be recorded separately; unit tests do not establish those outcomes.
