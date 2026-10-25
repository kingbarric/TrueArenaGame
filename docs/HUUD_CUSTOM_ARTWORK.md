# Huud custom UI artwork

The app renders its own orange, gold and cream pictograms instead of operating-system emoji. Sixty transparent PNGs were generated for PlayHuud; prompts are recorded in `HUUD_CUSTOM_ARTWORK_PROMPTS.json`. Existing custom navigation and game artwork is reused where appropriate.

`HuudArt` maps the existing saved avatar, reaction and game identifiers to artwork. `HuudSymbol` renders a sized image and `HuudText` embeds it into app-authored copy. Stored identifiers and network payloads remain compatible. Actual player messages, uploaded photos, chess pieces and Whot card shapes retain their content. The Tell has thirty distinct choices, including original vector sigils drawn in `HuudSignalArt`.

Images are bundled so empty states and navigation work without an asset download. They keep transparency and are decoded to their displayed physical size. Inline art follows text scaling, direction and wrapping, with spoken accessibility labels. The room renderer embeds the same host crown rather than using an emoji font.

## Visual QA

Run the actual empty Live and Huud screens with a local in-memory API:

```sh
cd app
flutter run -t lib/dev/huud_art_preview.dart --dart-define=HUUD_DARK_PREVIEW=true
```

The fixture has no real sign-in, messages, notifications or backend writes. Its Artwork tab shows the saved profile presets. Omit the dark flag for the light theme.

## Validation

- All 460 Flutter tests pass, including bundled artwork, alpha channels, distinct saved presets and Tell choices, accessible empty states, narrow layouts at 2x text size and unchanged user-authored emoji.
- Six Huud room renderer tests pass and TypeScript checks pass.
- The small-screen results test waits for the final scroll layout; the hair recovery test targets the readable category name.
