# Huudpoly release branding

Prepared 17 October 2026 at the account holder's request to replace the previous third-party game branding before App Store submission.

The property-trading game is presented as **Huudpoly**. The catalog, badges, lobby labels, feed names, board centre and server-generated display text use this title. The former character icon is removed from bundled assets. At the user’s request, the replacement icon is the user-supplied image, installed as `app/assets/images/game_icons/huudpoly.png`.

The board uses fictional neighbourhood addresses, original card descriptions, Opportunity and Neighbourhood decks, a Hub starting square, a Rest Stop and a navy centre with a distinct muted district palette. Card effects, board-space IDs, game rules and the internal `monopoly` identifier remain stable for existing clients and checkpoint recovery. Source class names and asset directory names are internal implementation details, not public game branding.

The earlier, superseded concept was generated using the built-in image-generation tool and inspected before integration. That concept contained buildings, a tree and a key. It is not the final icon selected by the user. The existing Roboto font licence and generated walnut texture provenance remain available in their asset directories. This document records the replacement work; it is not a trademark registration or a legal clearance opinion.

## Superseded concept generation prompt

Use case: stylized-concept. Create a polished square mobile board-game catalog illustration for PlayHuud's original property-trading game, Huud Estates. A charming miniature neighbourhood of three sculpted buildings: a terracotta townhouse, a teal apartment building and a golden modern tower on an original rounded hexagonal plaza, with a little tree and a single oversized brass key leaning in front. Warm orange, teal and cream palette, clean playful premium 3D game asset, bold readable silhouette at small icon size, centred composition filling most of square, softly shaded. No people, no mascots, no top hats, no moustaches, no money notes, no red rectangular wordmark, no branded board, no logos, no lettering or text. Transparent background with clean alpha; isolated building cluster.

## Submission handling

Build 2026101702 was uploaded before this replacement and must not be selected for release. Build and verify a newer package containing this work. Replace any games-screen screenshots showing the former artwork before uploading store screenshots.

Backend naming and board/card text must be deployed with this change because clients receive those values in authoritative game snapshots.


## Final icon selection

On 17 October 2026 the user supplied `codex-clipboard-1481ee94-1668-49ee-b637-1cd0cd42e759.png` and explicitly selected the title Huudpoly. That image replaces the earlier generated building-cluster concept described above. The generation prompt above records the superseded concept, not the provenance of the final icon. The user subsequently explicitly confirmed that they own or have the necessary permissions for the new Huudpoly image and the other artwork/audio included in PlayHuud. Apple’s content-rights declaration was saved based on that confirmation. This records the user’s attestation, not an independent licence audit or trademark clearance.

## Uploaded package

Version 1.0.1 (2026101705) was built from the current workspace, uploaded and processed by Apple, and selected on the App Store version. The packaged Huudpoly PNG was verified against the supplied image hash, and the former Monopoly icon was absent. Current iPhone/iPad catalog screenshots were captured. The App Store icon uses the home-screen PlayHuud wordmark composed on a navy square, saved at `app/assets/images/branding/playhuud-appstore.png`.
