# Huud 3D room

First phone delivery: 1.0.1 (2026101401), commit a1b0e272298a15c1edae0e6c69d640e34262645a, test API. Installation and launch confirmed with CoreDevice; the installed bundle version was read back from the phone. Renderer HTML and compiled test API were checked in the signed app. Test catalogue v34 is healthy; revised male assets were uploaded additively to Cloudflare R2.

People opens first, followed by Game and Chat. People and Chat each have a bounded inner scroll view. Profile, friend, gift, membership, voice permissions, unread messages, games and championships retain their existing flows. The first version uses seated avatars at a round table, head-level names, and speaking indications from actual LiveKit participant state. Simulator fixture indicators are explicitly debug-only.

The second version replaces the table seating with couches in a furnished sitting room, titled The Huud. Each room accommodates eight couch seats and four standing people; additional rooms remain reachable through paging. Sit, Stand and Walk affect your own avatar. Walking follows a bounded path around a low coffee table. Names follow head bones while moving. Reduced motion suppresses idle and walking animations. Geometry and textures are shared between instances; skeletons and tinted materials remain independent.

Avatar posture is sent on the existing Huud LiveKit data channel. It accepts only sit, stand or walk, applies the authenticated sender identity rather than a payload user ID, caps incoming packet size and ignores unrelated topics. Peers request current states when they join; movement stays usable locally if voice is unavailable. Remote clients animate the selected posture locally, rather than exchanging precise world coordinates. Exact multi-device path synchronization is outside this version.

Avatars currently use stable default body, hair, skin and outfit variations by account identity. They are not reconstructed from profile photographs or linked to a user's SlayHuud look selection.

Validation: 64 passing Huud tests and 90 passing renderer tests; no analyzer diagnostics in the new movement and canvas code. Coverage includes Huud widget regressions, bounded-panel and larger-group tests, movement-state tests, and source-model seating, independent-skeleton, overflow-spacing and walking-path checks. Existing renderer asset tests passed before the sitting-room changes. Final simulator visual review and a live two-phone movement check must be recorded separately; unit tests do not establish those outcomes.

## Profile avatar feature

Couch build 2026101402 was installed on the phone before this work started. Its simulator review exercised Sit, Stand and Walk, the twelve-person couch/standing layout and readable head labels. Profile build 2026101403 adds five choices (Ella, Elisabeth, Chloe, Alexander and Ethan) with ten complete outfits. Existing profile photos remain independent from the 3D Huud choice.

`GET/PATCH /api/v1/me/huud-avatar` reads and saves the authenticated account's selection. Flyway V54 stores it separately from SlayHuud career data. Member responses carry the saved avatar and outfit IDs; an inbox event refreshes active Huuds after a save, with the regular poll as fallback. The room uses the same dressed look as the Profile preview. Active looks share body vertex attributes and reuse prototypes; inactive prototypes are released. Loading is limited to two concurrent prototypes.

New Huuds explicitly start with `background=blank`. V55 also makes this the database default; Disco is an explicit choice. Existing migrations were preserved unchanged.

Validation: all 50 presets resolve to compatible wardrobe items and bind within metre-scale bounds in seated, standing and walking poses; 91 renderer tests pass. Profile selection, explicit saving, failed-save retry and the real Profile entry pass widget tests. Huud regressions pass. A real isolated Postgres/Redis check verifies schema upgrades, the authenticated save endpoint, account isolation, saved choices in member responses, blank defaults and the live avatar-change event.

Delivery preference: install each completed feature build on the user's phone before starting the next feature, using the test API. A locked device may need unlocking to launch the installed app. Final device and simulator checks should be recorded separately from automated checks.

Outfit refinement build 2026101404 regenerates independent dye uniforms on each cloned material, keeping room colours consistent with the Profile preview. Regular trousers replace patterned harem pieces in the ten presets. A development browser fixture renders the actual delivered GLBs through the same room renderer; its twelve-person scene was visually checked, including Ethan/Evening and Elisabeth/City Casual standing. The fixture is `slay-renderer/huud-preview.html` and uses generated delivered files, without signing in or changing real account preferences. Native Profile flows pass widget tests; a final native simulator visual check remains pending while the Mac is locked. Renderer tests: 92 passing; all 50 updated combinations pass seated/standing/walking checks.
