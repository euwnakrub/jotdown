# Jot app icon

Created with the built-in image_gen tool. Current design: an off-white **J** beside a warm-yellow **down arrow that doubles as a fountain-pen nib**, on a graphite rounded-square tile. The small yellow accent represents creativity; the exterior is transparent.

## Files

- `Jot-source.png`: selected generated image (1254 × 1254), preserving its alpha.
- `Jot-1024.png`: 1024 × 1024 PNG.
- `../AppIcon.icns`: macOS icon containing all ten image representations.
- `../../app.iconset/`: standard macOS sizes from 16 to 1024 pixels, including Retina variants.
- `../../build/Jot-icon-assets.zip`: complete current asset package.
- `../../build/Jot-icon-assets-before-j-pen.zip`: backup of the previous document/M/pencil design.

The source was resized using macOS `sips`, preserving transparency. The ICNS container was packed directly after `iconutil` compilation reported “Invalid Iconset” in this environment. The 16- and 32-pixel standard representations use legacy RGB/alpha chunks; the remaining eight use PNG chunks. The resulting ICNS was extracted with macOS `iconutil`, and all ten decoded images were verified pixel-for-pixel against the source iconset.

This asset package updates the requested root `app.iconset/`. The existing app build still uses its separate procedural icon in `scripts/make-icon.swift`.

## Generation prompt

Built-in image_gen edit using the previous document/M/pencil icon as the reference:

```text
Use case: logo-brand
Asset type: one finished macOS application icon for Jot, a Markdown writing app, square 1024 x 1024.
Input image 1: existing icon to redesign. Preserve its graphite rounded-square tile, quiet satin finish, balanced transparent margin, and restrained off-white palette. Replace the document/M/pencil graphic completely.
Primary request: blend the uppercase letter J, a downward arrow, and a pen into one clean memorable logo, with a small warm-yellow creative accent.
Design: a bold beautifully proportioned off-white uppercase J on the left, unmistakable J with a generous curved lower hook and short top bar. Closely paired on the right is a vertical downward-pointing fountain pen, stylized so its broad nib is also a clear downward arrowhead. The fountain pen/arrow is warm butter-yellow to soft golden-yellow; its simple short shaft and broad pointed nib form the down-arrow silhouette. One small graphite breather hole and a fine straight central slit make the arrowhead read as a fountain pen nib. The pen-arrow is a compact supporting part of the monogram, narrower than the J, and yellow remains a restrained accent, roughly 6–10 percent of the whole tile. Together the J and pen-arrow form a single balanced, tightly composed symbol, visually similar in readability to J plus a down arrow, with careful negative space.
Style: premium contemporary minimal app icon, vector-like precise contours, broad simple shapes, nearly flat with only extremely subtle satin shading. Strong legibility at 32 pixels. Front-on orthographic view, absolutely no perspective.
Composition: center the complete symbol optically inside the tile; give the symbol generous breathing room. Smooth graphite tile occupies about 82 percent of canvas width and height with equal transparent margins. Keep the full mark inside tile.
Palette: deep graphite, warm off-white, and a modest amount of warm yellow. No orange, no rainbow.
Constraints: no paper or document, no M, no extra diagonal pencil, no extra text or app name, no lightbulb, no decorative stars, no additional glyphs, no watermark, no mockup, no white outside border, no external shadow, no noisy texture. Keep real clean alpha transparency outside the tile, no checkerboard background. Output one polished icon only.
```

## Final refinement prompt

Built-in image_gen edit using the first J/pen result as the reference. This selected result is `Jot-source.png`:

```text
Use case: logo-brand
Asset type: final macOS app icon, edit the provided icon.
Make ONE targeted design adjustment: refine only the golden-yellow pen at the right of the J so its outer silhouette clearly reads as a DOWN ARROW (↓), while its inner detail reads as a fountain-pen nib.
The current cap is too wide. Replace it with a narrower vertical yellow shaft, centered over a substantially wider arrowhead. Join shaft and arrowhead as one continuous shape. The arrowhead must have clear broad horizontal shoulders and two clean diagonal sides converging to a centered downward point, with gently softened corners. The golden arrowhead is also a pen nib: retain a small graphite circular breather hole in its center and a thin straight graphite slit from that hole down to the point. This is one integrated downward-arrow/fountain-pen symbol, not separate objects. Keep the overall pen-arrow bounding box approximately where the old pen was, balanced beside the J. Restrained warm yellow.
Strict invariants: keep the exact off-white uppercase J design and position, keep the same dark graphite rounded-square tile, same dimensions and transparent outer margins, same subtle satin finish and overall balance. Do not add anything. No text, no extra icons, no paper, no decorative sparkles. Clean precise smooth geometry, legible at small icon sizes. True alpha transparency outside the tile. Output only the single complete finished icon.
```

