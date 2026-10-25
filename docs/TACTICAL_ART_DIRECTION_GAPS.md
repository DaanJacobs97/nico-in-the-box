# Tactical RPG art direction comparison

Reference: `ART DIRECTION ASSETS/index.html`. This compares the Flutter game view with the reference page after the UI corrections in this work pass.

## Remaining visual differences

- **Battlefield illustration:** the reference uses a shaded, atmospheric arena with custom scene shapes and a soft vignette. The game uses generated, square terrain cells with stronger borders and simple terrain icons. Matching the scene art will require authored terrain and prop assets.
- **Character art style:** the reference uses clean illustrated busts. The game uses the supplied pixel-art PNG sprites. The activation cards now crop the supplied art into portrait windows, but the underlying art style still differs.
- **Hand composition:** the reference fans its action cards with pronounced perspective, overlap, and larger card faces. The game uses a smaller, flatter horizontal hand with tilt and lift transforms. Its card backs, symbols, and borders remain less detailed than the reference.
- **Battlefield/HUD boundary:** the reference reserves a defined lower area for the hand. This game keeps the map full-screen under translucent controls, as requested. The two layouts will continue to differ in how much visible battlefield sits behind the cards.
- **Scene depth and effects:** the reference layers silhouettes, lighting, and stronger vignette behind the characters. The game currently has flat terrain colors and sprite overlays, without equivalent props, shadows, or scene lighting.

## Corrections made in this pass

- Map taps are converted through the transformed map canvas itself, so zooming, panning, or changing map dimensions no longer depends on the old viewport-centering calculation.
- The HUD backdrop is translucent and ignores pointer input. While a card is targeting, the faded action cards stop intercepting map clicks.
- The hand collapses by clipping a full-size layout in a bottom-aligned viewport, avoiding the short-height `RenderFlex` overflow reported in the supplied debug output.
- Trap targets use red highlights, include legal route tiles, and map hit testing now respects the tile under tall character art.
- Unit activation cards now show a cropped portrait, role, AP, HP, movement, weapon range, attack, weapon, mana, deck size, and drag cue.

These code changes still need a visual run in the app to confirm their final appearance at the user's Mac window size.
