# Classic depth concept — image prompt

Generated with the built-in imagegen tool on 10 October 2026. This is a planning mockup, not an implemented game screen.

The generation prompt specified a single portrait PlayHuud mobile UI with the following design requirements:

- Familiar classic square property-trading board with four corners, perimeter spaces and a green centre; a gentle near-overhead tilt.
- Warm walnut base, ivory beveled tiles, raised property bands, brass trim, contact shadows, reflective metal tokens, miniature green houses and red hotels.
- PlayHuud wine-black background `#16100F`, maroon accents `#C02B52`, warm cream typography `#F6EAE3` and brass/gold `#D9A441`.
- Header text “Eric's Huud”, “MONOPOLY” and “12 watching”. Four player chips: Eric, Ada, Chidi and Sarah; Ada highlighted as the current player with a mic indicator.
- Mostly open green board centre, an embossed wordmark, two ivory dice and Chance/Community card decks.
- One highlighted property, with a readable deed card below the board: “NORTH AVENUE”, “PRICE $240”, “RENT $20”, “Ada landed on an unowned property”. Buying actions: “Buy $240” and “Auction”; no simultaneous Roll Dice primary action.
- Bottom controls “Properties”, “Trade”, “Huud Chat” and microphone.
- Premium toy-scale 3D depth, restrained lighting, clear typography and thumb-friendly controls. No phone hardware, collage, excessive particles or casino imagery.

These property values and the generated board artwork are placeholders for design review. The final board must use the agreed rules and real match state.

## Full generation prompt

```text
Use case: ui-mockup.
Asset type: one high-fidelity portrait mobile game screen concept for PlayHuud, a social gaming app. This is a brand-new design based on the user's preference for a CLASSIC Monopoly-style square board made richer and more dimensional. Render ONE coherent full-screen portrait app UI, approximately 1024x1536. No phone hardware, no collage, no annotations outside the UI.

Design direction: "Classic Table — 3D Depth". The familiar square property trading board is the hero. A beautifully crafted physical tabletop game rendered in restrained, believable 3D, framed by polished mobile app controls. Keep the board recognizable as a traditional Monopoly-style board: an orderly square perimeter of forty spaces, ten spaces between each pair of corner boundaries counting the corner at the beginning, four large corner squares, color strips on property spaces, small railroad and utility spaces, GO, JAIL, FREE PARKING, and GO TO JAIL corners. Straight grid aligned square board, NOT a diamond, not a freeform path or sprawling city. Gentle elevated overhead camera: near top-down, only a modest tilt so all four sides remain visible, no extreme perspective, no obscured perimeter tiles.

Palette: match PlayHuud's warm classic identity: deep wine-black #16100F background, maroon #C02B52 accents, warm cream typography #F6EAE3, muted brass/gold #D9A441, walnut tabletop, mint-green classic board center, ivory raised property tiles. Property groups use restrained distinct brown, pink, orange, red, yellow, green and blue. No purple interface. Excellent readable contrast.

Composition:
Top 12%: compact app header with back arrow, title "Eric's Huud", small subtitle "MONOPOLY", and a voice waveform icon. A small unobtrusive badge says "12 watching". Below, a horizontal row of FOUR tasteful player chips: Eric, Ada, Chidi, Sarah, showing a distinct token icon and a dollar balance for each. Ada is the current player, highlighted with a maroon rim. Show a little illuminated microphone indicator near one avatar; game players already have mic access.
Middle 55%: make the board very large, taking nearly the full screen width with minimal side padding, set above a warm walnut tabletop inset. Board has an actual visible layered thickness, ivory tile faces with beveled edges, fine dark printed labels, slightly raised color bands, soft contact shadows and subtle reflections. A tasteful thin brass inner border. Metallic token miniatures: a silver car, brass hat, enamel dog and chrome ship, small and convincingly resting on individual spaces. A few miniature GREEN houses and RED hotels stand on their properties along the outer edge, carefully positioned to keep paths and labels legible. Delicate colored ownership notches, not fluorescent flood lighting. One blue property square is selected and has a subtle warm glow and precise raised outline. The center is mostly open soft green felt, with a restrained embossed "MONOPOLY" wordmark, two tactile ivory dice showing a prior roll, and two small physical card decks labeled "CHANCE" and "COMMUNITY". Rich materials, directional warm light from upper left, naturally soft shadows, ambient occlusion beneath objects, fine surface detail, no overdone sparkle. Avoid a giant city in the middle.
Bottom 28%: a clear context card describing the currently landed-on property, distinct from tiny board print. It is an inset warm ivory property deed card with a dark-blue header band, label "NORTH AVENUE", and large legible proposed values "PRICE $240" and "RENT $20". Smaller caption "Ada landed on an unowned property". Two large thumb-friendly actions side by side: primary maroon raised button "Buy $240" with a tasteful physical depth shadow; secondary outlined ivory button "Auction". This represents a buying decision AFTER a roll, so do NOT show a simultaneous Roll Dice primary action. Below, a discreet compact row of controls: "Properties", "Trade", "Huud Chat", with a microphone button. Keep all controls aligned, spacious, and readable.

Style: premium production-ready mobile game UI mockup, classic board-game charm with satisfying tactile depth, realistic toy-scale 3D, excellent restrained visual hierarchy, clear numbers, crisp typography, rounded cards with the PlayHuud playful solid outlined button language. Make the board visually richer through material, tile bevels, shadows, token reflections, and layered lighting, while retaining a useful overview. Property detail card ensures readability on a small phone. Screen should feel immersive and expensive, still practical for gameplay. No fabricated large status popups, no garbled large text, no duplicate boards, no excessive particles, no casino imagery, no real-money betting indicators.
```
