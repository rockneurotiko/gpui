# Fork changes on `hover-styles` (design-parity capabilities)

Commits on top of `22a5ff2`, in order. None are pushed yet.

## Changes

### Fonts
- **`eb6e629` font_family + font loading.** `font_family` style (string) with `font-[Name]`
  (`_` becomes a space; quotes and a `family-name:` prefix are stripped; digits-only is unknown).
  New display option `fonts:` (files or directories of `.ttf/.otf/.ttc`) loads font bytes into the
  GPUI text system at start, deduplicated by content. Backed by a `:string` style value type, a
  `load_fonts` NIF and `WindowCommand::LoadFonts`.
- **`eda5fa1` full weight scale.** `font_weight` gains `thin`, `extra_light`, `extra_bold`, `black`
  (`font-thin/extralight/extrabold/black`, `font-[100..900]`).
- **`2c55936` rich-text run family.** `GPUI.Text.RichRun` gains `font_family` (inline mono spans in
  a flowing `ui_rich_text` paragraph).
- **`1958703` generic family classes removed.** `font-sans/serif/mono` emitted generic names that
  GPUI's Linux text system never matches, so they silently did nothing. The library does no font
  resolution: family names must match an installed or `fonts:`-loaded family exactly.

### Shadows, borders, text
- **`610520e` `box_shadow`.** List of `{x, y, blur, spread, color, inset}`; renders through GPUI
  `BoxShadow` (follows corner radius). Tailwind: `shadow-none/2xs/xs/sm/shadow/md/lg/xl/2xl/inner`
  (v3 values; v4 for `2xs`/`xs`) and arbitrary `shadow-[0_1px_2px_#hex]` (multi-layer, `inset`,
  `rgb()/rgba()`).
- **`344a6d6` borders.** Per-side widths (`border-t|b|l|r|x|y`, `-0|1|2|4|8|[Npx]`) and
  `border-solid` / `border-dashed`.
- **`7156e31` text styles.** `italic`/`not-italic`, `underline`, `line-through`, `no-underline`,
  `uppercase`/`lowercase`/`capitalize`/`normal-case` (case transform applied natively to a text
  node's own string).

### State styles
- **`9628ed2`** `focus:` and `focus-within:` `bg-*`, `text-*`, `border-*`.
- **`e2acf42`** `hover:`, `focus:`, `focus-within:` `opacity-*`.
- **`f28d624`** `active:` (pressed) `bg-*`, `text-*`, `border-*`, `opacity-*`.
- **`0cc92e8`** `focus-visible:` `bg-*`, `text-*`, `border-*`, `opacity-*`; replaces the default
  blue focus ring when set (the default stays otherwise).

### Components and icons
- **`f899112` select/input width.** `class`/`style` already reached `ui_select`/`ui_input`; the
  layout wrapper ignored the width. It is now forwarded, so `w-[260px] h-[36px]` lays out at
  260x36 without a wrapper div. `ui_input masked: true` is documented as the masked-entry path.
- **`9db4b64` `<svg>` tag.** Inline SVG markup (`source`), painted as a mask in the element's
  text colour, so `text-*`, `hover:text-*`, `focus:text-*` and `focus-within:text-*` tint it.
  `img` is untouched.

### Closed with no code
- `ui_virtual_list` already covers picker and palette scrolling: wheel scroll, keyboard reveal
  (set `reveal_index` for app-driven selection), section headers as extra disabled rows of the
  same height.

## Gaps and limits

### Not possible with the pinned GPUI (Zed `1662f5f`)
- **Letter-spacing (`tracking-*`):** no support in GPUI. The class stays unknown.
- **Variable fonts:** the Linux text backend never applies the weight axis, so weights only show
  with static font files. The default font on Linux may be variable, so apps must bundle a static
  family via `fonts:` and select it with `font-[Name]`.
- **Per-side border colours:** one border colour for all drawn sides.
- **`overflow-hidden` clips to a rectangle,** not to rounded corners. Workaround: give children
  matching rounded corners.
- **Plain-text selection:** only `rich_text` is selectable; there is no `select-text`.
- **Per-run font size** in rich text is not supported.

### Not built
- `ring-*` / outline (GPUI has no outline; a ring could later be a focus-state box shadow).
- Inheritance of `text-transform` (applies only to a text node's own string, not rich text).
- Scrollbar or scroll cue on `ui_virtual_list`; offset, scroll event and scroll-to-child on plain
  `scroll`.
- `ui_virtual_list` rows are one uniform height.
- `masked` on the raw `text_input`.
- SVG resource references (`<svg>` takes inline markup only); no bundled icon set.
- Extra cursors (`cursor-grab`, `-wait`, `-crosshair`, ...); five are supported.
- `hover:shadow-*`, `shadow-<color>`, and a `dark:` variant (theme-specific classes are the app's
  job, e.g. `shadow-none` in dark).
- Focus styles on `<scroll>`; `active:` and `hover:` only apply on the container path.
- `focus:` and its variants only work on elements that own a focus handle (button,
  click-activatable containers, focusable inputs); plain divs do nothing. The sidebar item always
  gets the default focus ring.
- Select/input internals other than what a refinement on the field container reaches.

### Unmet acceptance criteria
- Distinct 400/500/600/700 glyph weights proven by a test: skipped, no static multi-weight OFL
  fixture and no e2e harness in this checkout.
- `focus-within:ring-2`: not built (see `ring-*`).
- tsg-side criteria (screens match design, divider divs and raster icon code removed) belong to the
  app, not the fork.

### Verification limits
- Nothing was checked visually. Native harness tests prove styles are accepted and layout, not
  appearance: shadows, focus/active/hover colours, opacity, text transform, borders and the svg
  tint are all unconfirmed as rendered pixels. `rounded-*`, border colour on selects/inputs, and
  focus changing colour were verified at class-normalisation or acceptance level only.
- `mix gpui.release.check` and `mix gpui.test.packages` were not run.
- 6 native tests (Split divider drag, 2 Slider drag, 3 Controls) fail on the baseline as well, and
  `mix ci` does not run the native suite (run it with
  `MIX_ENV=test MIX_TARGET=native_test mix test <file> --include native`).
- `BackendTest` "starts and stops a native runtime" flaked with `gpui_command_timeout` in two
  `mix ci` runs; it passes alone and on rerun.
- `mix ci` needs Elixir 1.20 (`~/.local/share/mise/installs/elixir/1.20.5-otp-29/bin` first on
  `PATH`); the default mise Elixir 1.19.4 fails `mix.exs`.

## Rollout (per `AGENTS.md`)
`just gen` is already committed. Push, `just gpui-lock`, commit and push the lock, then
`just gpui-update` in `trip-service-cli/apps/tsg`. `just rust-check` only passes after the push,
because it builds against the pushed `gpui_core`.
