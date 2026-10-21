# dsmn redesign QA

Final result: passed

## Social preview revision

- Replaced the old social artwork reference with `public/assets/dsmn-social-preview-pixel.png`, an exact 1200 × 630 export matching the new typography, heartbeat, paper palette, dithered laptop, and menu preview.
- The editable source in `scripts/social-preview.html` reuses the actual site fonts, styles, assets, and paused dither shader. It runs no analytics and is excluded from production page entry points.
- Inspected the full exported card. An initial copy-layer overlap was corrected before the final capture. The headline, product description, logo, menu, and footer are visible with no clipping; no actionable P0/P1/P2 findings remain.
- Expect verified a 1200 × 630 viewport and image at device scale factor 1, loaded Geist Pixel Square, the completed dither frame, and no browser console errors.
- Open Graph and Twitter metadata use the same new absolute image URL and descriptive alt text. The new filename separates this artwork from previously cached previews.
- Production build, exported dimensions and format, metadata references, and whitespace checks pass.

## Pixel heartbeat revision

The user subsequently requested a pixel heartbeat logo matching the site's type. This supersedes the original-logo requirement recorded in the earlier redesign history below.

- Added a stepped pulse drawn on a 28 × 20 grid and set the wordmark in Geist Pixel Square, matching the headline. Removed the unused Pixelify dependency.
- Applied the mark to the website header, interactive menu preview, legal page, and 404 page. Added an optically simplified 16 px SVG favicon and a 180 px touch icon. Native app files are unchanged.
- The header mark stays still. While the preview is active, a brief orange trace crosses the menu mark every 4.8 seconds. Stop, manual motion pause, and system reduced motion disable it.
- Visually inspected desktop and narrow mobile captures in `pulse-logo/desktop-1424.png` and `pulse-logo/desktop-320.png`. The mark and wordmark stay legible without crowding navigation. Widths 1424, 390, and 320 all have document width equal to viewport width.
- An isolated Expect browser verified loaded assets, wordmark font, active/stopped/restarted animation states, manual pause, system reduced motion, and both secondary-page marks. No console errors were captured. Evidence: `pulse-logo/results.json`.
- `npm run build`, all seven existing analytics/feedback tests, and `git diff --check` pass for this revision.
- No actionable P0/P1/P2 findings remain in this revision.

## Visual target and evidence

- Source visual reference: maintainer's local 1422 × 1106 px image (not distributed).
- Implementation: `http://localhost:5173/`, branch `jb/dither-redesign`.
- Evidence: historical maintainer-local captures, not included in the repository.
- Current desktop capture: `pulse-logo/desktop-1424.png`, 1424 × 1104 px, matching CSS viewport, device scale factor 1. The preceding typography comparison used `font-revision/1424.png`, with the source resized by less than 0.2% to the same dimensions.
- Final state: light theme, menu expanded, Codex selected, approximately 16 minutes remaining, scroll position zero. The screenshot freezes a frame of the live animation.
- Full-view comparison: `font-revision/comparison.png` places the normalized source on the left and implementation on the right in one image. Both were opened and visually compared together. `font-revision/headline-comparison.png` provides the focused typography comparison.
- Focused comparisons: `comparison-menu.png` and `comparison-laptop.png`, taken from the same source and implementation. These were also opened together to inspect the small controls and raster treatment.
- Responsive captures: `mobile-final-320.png` (320 × 844 px), `mobile-final-390.png` (390 × 3489 px full page, CSS viewport 390 × 844). Additional checks at 768, 1024, and 1424 CSS px wide found no horizontal overflow.
- Secondary routes: `legal-mobile.png`, `404-mobile.png`.
- Browser verification output: `expect-results.json`.

## Findings and comparison history

1. Initial desktop comparison (`comparison-01.png`) found two P2 issues: the headline pushed the composition below the reference, and the dither conversion washed out the laptop silhouette. Reduced the desktop headline from approximately 105–108 px to 96 px and tightened its margins. Adjusted luminance conversion and the dither grid to retain the laptop's form.
2. Recaptured the same viewport and compared again (`comparison-02.png`). The headline hierarchy, closed laptop, dark menu, and integration strip now fit the intended composition. The activity line was raised to pass through the laptop scene.
3. Responsive testing found a P2 issue at 320 px: the headline wrapped to three lines and the navigation label wrapped. Lowered the headline's minimum to 46 px and compacted the header below 380 px. `mobile-final-320.png` verifies the two-line headline and single-line navigation after the fix. Document width equals viewport width.
4. Final comparison used clean, native-density Expect captures (`comparison-final.png` and focused crops). No actionable P0/P1/P2 findings remain.
5. The user flagged the Pixelify headline's readability as worse than the image preview. Reclassified the letterform difference as P2 and replaced headings with locally served Geist Pixel Square from the official `geist@1.7.2` package. Browser weight synthesis is enabled only for headings to approximate the mock's heavier strokes. Pixelify remains limited to the existing wordmark. Recaptured and compared the full composition and headline in `font-revision/`; 320 and 390 px captures verify the headline still occupies two lines without overflow. Font loading, console, and build checks pass.

Early in-app browser screenshots contained extra canvas padding and an unusual density conversion (CSS 1424 × 1104, reported DPR 0.8, raw image 1779 × 1379). For the initial comparisons, the visible upper-left 890 × 690 content was normalized to the CSS viewport. The final comparison replaces this evidence with a clean 1424 × 1104 capture at DPR 1.

## Required fidelity surfaces

- **Fonts and typography:** Geist Pixel Square provides conventional, readable pixel letterforms for headings and now the wordmark; IBM Plex Mono provides small site copy. System sans and monospace keep the menu legible. The headline retains the target's two-line hierarchy at 1424, 390, and 320 px. The generated reference is not a precise font specification, but the new family closely follows its capital T, lowercase forms, and heavier strokes. Headline comparisons and measurements are in `font-revision/`, including `results.json`; the desktop headline's first line measures 566.58 px at 96 px type. The current lockup is captured in `pulse-logo/`.
- **Spacing and layout:** Centered hero, left closed laptop, right dark menu, line-bounded integration strip, and editorial introduction preserve the selected composition. The additional preview caption accounts for a small increase in stage height. Desktop, tablet, and mobile controls remain within the page; mobile deliberately stacks the laptop and menu.
- **Colors and tokens:** Warm paper `#f1f0e7`, ink `#20231e`, sage `#626b55`, and orange `#d85a38`. Dark panel and pale labels preserve the target's contrast and hierarchy. The live page uses a flat paper surface rather than the mock image's uneven lighting.
- **Image quality and assets:** A generated 1536 × 640 WebP of a closed MacBook is processed by a WebGL Bayer dither shader. The subject, crop, scale, and silhouette match the direction. Ordered animated dithering intentionally differs from the mock's irregular stippling. A new vector pixel heartbeat now replaces the website logo and favicon at the user's request. Interface icons come from Pixelarticons; icon and font licenses are included.
- **Copy and content:** Hero copy follows the selected reference. Setup and FAQ copy were grounded in the neighboring native app: activity renews a bounded timer, and sleep is allowed after expiry. The menu is explicitly an interactive preview; it never changes the computer's sleep state. The native app has not been redesigned in this change.

## Interaction verification

Passed in an isolated Expect browser session:

- Stop changes status to sleep allowed and stops the activity stream; restart starts 20 minutes.
- 30-minute and 90-minute presets show the corresponding countdown.
- All four agent buttons update the activity source and restart the preview timer.
- Menu opens and closes; Escape closes it from a focused control.
- Custom duration rejects empty input, zero, negative values, fractions, and values above 720. It accepts 720 and 1 minute.
- Escape closes the custom dialog and restores focus to Custom.
- A one-minute timer expires at 00:00, switches the stage inactive, and pauses the stream. Verified with Playwright's clock through Expect.
- Pause/Resume motion works. Emulated system reduced motion pauses the page, disables the override button, and removes CSS animation.
- All six FAQ disclosures open; Legal, the 404 page, and Back home work.
- Browser error log: no console errors captured in the final run.
- Download endpoint: HTTP 200, Apple disk image content type and attachment filename `dsmn-latest.dmg`; verified with a HEAD request without downloading the installer.

The initial Expect agent adapter failed to initialize. A shared CLI browser also collided with an unrelated test session. Verification therefore used a dedicated Expect MCP process and browser. Early assertions for reduced motion ran before the media-change event was delivered; the final checks wait for the rendered state. These were test harness issues, not accepted product failures. The in-app browser disconnected before the final mobile pass, so the final captures use Expect's Chromium browser.

## Build checks

- `npm run build`: passed.
- `npm test`: all 7 existing analytics/feedback tests passed.
- `git diff --check`: passed.

## Follow-up polish and scope

- P3: irregular print-like stippling could be explored further if the user prefers it to this animated Bayer treatment.
- Social preview artwork now matches the redesigned website; see the social preview revision above.
- Native macOS behavior and native menu implementation are outside this website prototype; no native app files changed.
- Visual QA covered the local preview on port 5173. Deployment was not part of this validation.

## Implementation checklist

- [x] Implement the subsequently requested pixel heartbeat identity; keep the original asset files available.
- [x] Implement the selected light direction with the prominent menu preview.
- [x] Add animated dithering and working preview controls.
- [x] Respect reduced motion and provide a manual pause.
- [x] Fix visual and mobile findings, then recapture.
- [x] Check secondary pages, download route, production build, and existing tests.
