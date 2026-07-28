# Design Revamp: Glassmorphism — Design Spec

Date: 2026-07-28
Status: Draft for review
Scope: Full visual overhaul of the entire Meowes app + a new glass bottom-nav shell.

## 1. Overview

Meowes is a Splitwise-style expense-splitting app (Flutter, Riverpod, Supabase). This
is a **full aesthetic overhaul**: retire the current warm cream + coral "cat" identity
entirely and rebuild the app's visual language around **glassmorphism** — a rich
gradient backdrop with frosted, translucent panels — in both light and dark modes.

This spec covers visuals, a new design-token system, shared glass components, a new
floating glass tab-bar navigation shell (with the new tab screens it requires), and a
screen-by-screen restyle. It does **not** change data, repositories, Supabase RPCs, or
business logic.

### Design read (taste-skill §0.B)
Premium-consumer social-finance mobile app, redesign-**overhaul** mode, **glassmorphism**
language grounded in three references (Aerium smart-home, Pilates, Ripple). Built on
Flutter/Material 3 (the taste skill scopes native mobile to Material/HIG directly, so we
keep Material 3 and port only the skill's judgment: one locked accent, controlled
saturation, real type, full interactive states, honest glass with fallbacks).

### Dials
- `DESIGN_VARIANCE: 4` — product UI; clarity and consistency over compositional flourish.
- `MOTION_INTENSITY: 4` — fluid micro-interactions, all reduced-motion aware.
- `VISUAL_DENSITY: 3` — money data breathes; generous spacing.

### Decisions locked with the user
- Direction: full overhaul → glassmorphism (references provided).
- Cat identity: **dropped entirely** (no paws, no mascot, no cat emoji). Pure typographic brand.
- Type: **Onest** (UI/body) + **Space Grotesk** (headlines + money numerals).
- Theme: **both light and dark**, following system (`ThemeMode.system`). Dark is the hero expression; light is a soft-gradient glass variant.
- Brand accent: **indigo** (`#5B7CFA` → `#6E8BFF` gradient) — collision-free with money semantics.
- Money semantics fixed: **green = owed to you, red = you owe, neutral-grey = settled**.
- Navigation: **build the floating glass tab dock** (Home / Friends / Groups / Activity / Profile), including the new tab screens this requires.

## 2. Design tokens

Corners use ONE scale (Shape Consistency Lock). Neutrals are hue-biased toward the
indigo accent, not pure grey.

### 2.1 Dark mode (hero)
- Backdrop gradient: `#1E2233` (top) → `#0E0F16` (bottom), 165°.
- Ambient blobs (behind glass): indigo `#5B7CFA` @ 32% opacity, teal `#22B8A6` @ 20%. Heavily blurred, static.
- Glass card fill: white @ 7% (`0x12FFFFFF`); border: white @ 14%; top sheen: white @ 20% → transparent.
- Glass strong (dock, app bar, key panels): white @ 10%; border white @ 18%; sheen white @ 22%.
- Glass subtle (rows inside a glass card): white @ 6%, **no own blur** (see §4).
- Text: primary `#F5F6F8`, secondary white @ 60%, muted white @ 42%.
- Brand: gradient `#6E8BFF`→`#5B7CFA`; solid `#5B7CFA`; on-brand `#FFFFFF`.
- Positive `#4ADE80` (+tint green @ 16%); Negative `#FF7A7D` (+tint red @ 16%); Settled `#9BA0AA` (+tint white @ 8%).

### 2.2 Light mode (soft-gradient glass)
- Backdrop gradient: `#EEF1FA` (top) → `#E3E8F4` (bottom), 165°.
- Ambient blobs: indigo `#8FA6FF` @ 38%, teal `#7FE0D0` @ 30%.
- Glass card fill: white @ 55%; border: white @ 70%; sheen: white @ 60%.
- Glass strong: white @ 60%; border white @ 75%.
- Text: primary `#1A1C22`, secondary `#5A5F6B`, muted `#8A8F9C`.
- Brand: same indigo gradient; on-brand `#FFFFFF`.
- Positive `#0E9E6E` (+tint @ 14%); Negative `#E5484D` (+tint @ 14%); Settled `#8A8F9C`.

### 2.3 Radii (single scale)
- Panel / card: `24` (hero balance card `26`).
- Button / control / input: `14`.
- Pill / chip / segmented control / nav dock: stadium (fully rounded).
- Avatar: circle.

### 2.4 Spacing
Base unit 4. Screen horizontal padding `20`. Section gap `20–24`. Card inner padding `16–20`.
List row vertical padding `12`. Touch targets ≥ `48`.

## 3. Typography

Bundle the font files locally (do not rely on runtime `google_fonts` fetch, for offline
reliability). Both faces are SIL OFL, safe to bundle.

- Files: `assets/fonts/Onest-{Regular,Medium,SemiBold}.ttf`, `assets/fonts/SpaceGrotesk-{Regular,Medium,SemiBold,Bold}.ttf`. Declare in `pubspec.yaml` `flutter: fonts:`.
- **Onest** — UI/body (weights 400/500/600).
- **Space Grotesk** — display, headlines, and all money numerals (400/500/600/700).
- All digits use `FontFeature.tabularFigures()`.

Type scale:
| Role | Face / weight | Size |
|---|---|---|
| Hero balance | Space Grotesk 500, tabular | 40–44 |
| Screen title / greeting | Space Grotesk 600 | 20–24 |
| Money amount (rows) | Space Grotesk 600, tabular | 15 |
| Section label | Onest 500, uppercase, tracked | 11–12 |
| Body | Onest 400 | 14–15 (line-height 1.5) |
| Secondary / caption | Onest 400/500 | 12–13 |

No em-dashes anywhere in visible copy (taste-skill §9.G). No emoji.

## 4. Glassmorphism recipe (Flutter)

Primitive `GlassSurface`:
`ClipRRect(radius) → BackdropFilter(ImageFilter.blur(sigma)) → Container(color: glassFill, border, top-sheen gradient overlay)`.
Flutter has no inset box-shadow, so the top-edge "sheen" is a `LinearGradient` overlay
(white-opacity → transparent, top ~40%) plus a hairline `Border.all` for the edge.

Blur sigma: `~18` (cards), `~24–26` (strong/dock/app bar).

### Performance rules (mandatory)
`BackdropFilter` is expensive and compounds badly in scrolling lists. Therefore:
- The gradient backdrop + ambient blobs are a **plain painted layer** (cheap), rendered
  once per screen by `GlassBackground`. No blur there.
- Glass panels are for a **bounded set** of static surfaces per screen (balance card,
  app bar, dock, section panels). Target ≤ 3–4 live `BackdropFilter`s on screen.
- **Lists do not blur per row.** A list sits inside ONE glass card (single blur); rows
  use translucent fills + hairline dividers with **no** per-row `BackdropFilter`.

### Accessibility fallback (mandatory)
`GlassSurface` supports a `disableBlur` path that renders an opaque solid fill (using the
mode's surface color) with the same border/radius. It is enabled when:
- the platform exposes a "reduce transparency" signal (verify `MediaQueryData.reduceTransparency` availability at implementation; if absent, rely on the setting below), OR
- the in-app setting **Profile → Settings → Reduce transparency** is on.
Text contrast must pass WCAG AA in BOTH the glass and the solid-fallback rendering.

## 5. Iconography

- Drop all cat/paw imagery and every emoji (`👋`, `🐾`, etc.).
- One icon family, consistent visual weight: Material **outlined** icons (thin-line, matching the references). No hand-drawn SVG paths.
- Icon-only controls (bell, dock items) get semantic labels.

## 6. Motion (dial 4, all reduced-motion aware)

Every animation below collapses to instant/static when `MediaQuery.disableAnimations` is true.
- Page transitions: subtle fade + slide.
- Hero balance: count-up on load (motivated — draws the eye to the key figure).
- List first-load: short staggered fade-in.
- Buttons: `scale 0.98` on press (tactile feedback).
- Tab switch: `IndexedStack` + cross-fade; dock active-indicator slides between items.

## 7. Navigation architecture (new)

Introduce `HomeShell` (stateful): a `GlassBackground` + `IndexedStack` of 5 tabs + a
floating `GlassNavDock`. `RootScreen` routes to `HomeShell` (instead of `HomeScreen`)
after auth + profile checks. Center dock item is the brand **Add** action.

Tabs:
1. **Home** — overview/dashboard: greeting, overall-balance hero, recent-activity snippet, quick entries. (Reworked from today's Home, which currently also lists all friends + groups.)
2. **Friends** — full friends list with per-friend balances + add-friend entry. (New screen; friend content extracted from current Home.)
3. **Groups** — full groups list with net balances + create-group entry. (New screen; group content extracted from current Home.)
4. **Activity** — global activity feed. (New screen; data from existing activity/notification sources.)
5. **Profile** — user profile, summary stats, settings (incl. Reduce transparency toggle), sign out. (New screen; none exists today.)

This is an approved information-architecture change: Home's combined friends+groups list
splits into dedicated tabs, and Home becomes an overview.

## 8. Component inventory

Rework `lib/core/` (theme + widgets). Data/logic in feature screens is preserved; only
the presentation layer changes.

Theme:
- `app_theme.dart` → `AppTheme.light` + `AppTheme.dark`; `MaterialApp` gains `darkTheme` + `themeMode: ThemeMode.system`.
- New `GlassTokens` `ThemeExtension` holding: glassFill, glassBorder, glassSheen, blurSigma, gradientTop/Bottom, blobIndigo/blobTeal, brandGradient, positive/negative/settled + their tints. Light + dark instances. Accessed via `Theme.of(context).extension<GlassTokens>()!`.

Primitives (new):
- `GlassBackground` — gradient + ambient blobs (painted, no blur).
- `GlassSurface` — blur + fill + border + sheen, with `disableBlur` fallback.
- `GlassScaffold` — `GlassBackground` + transparent `Scaffold` + optional `GlassAppBar`.
- `GlassAppBar`, `GlassNavDock`, `GlassButton` (indigo gradient primary) + secondary/ghost glass button, `SegmentedPills` (split-type selector etc.), `SkeletonLoader` (shimmer for loading states).

Refactors (existing widgets → glass):
- `AppCard` → `GlassCard` (wraps `GlassSurface`).
- `BalanceSummaryCard` → glass hero; big Space Grotesk numeral; semantic color; clean "settled" state (no cat emoji — use an icon + text).
- `BalanceAmount` → Space Grotesk tabular, +/− semantic colors.
- `AppAvatar` / `AvatarStack` → retuned tint palette for glass, subtle ring.
- `SectionHeader` → small tracked uppercase label in muted token.
- `EmptyStateBox` → glass, outline icon (no cat), actionable copy.
- `app_outlined_button.dart` → folded into the glass button set.

## 9. Screen-by-screen restyle (content/logic preserved)

- **Sign-in** — glass backdrop; brand wordmark (typographic, no cat); glass provider buttons (Google/Apple).
- **Profile-setup** — glass form card; stepper as `SegmentedPills`; glass inputs.
- **Home (overview)** — greeting (Space Grotesk), glass balance hero (count-up), recent-activity snippet, quick entries to Friends/Groups.
- **Friends (new)** — glass list card of friends + balances; add-friend action; empty/loading/error states.
- **Groups (new)** — glass list card of groups + net balances; create-group action; states.
- **Activity (new)** — grouped activity feed in glass; date section labels; states.
- **Profile (new)** — glass profile header, stat tiles, settings list (incl. Reduce transparency), sign out.
- **Add-expense** — glass form; amount in Space Grotesk; payer/participant selectors; `SegmentedPills` for split type; states + inline validation errors.
- **Expense-detail** — glass summary; participant split list; edit/delete actions.
- **Group-detail** — glass header, members avatar stack, expenses list, smart-settle panel, add-expense action.
- **Create-group** — glass form; member selection; invite link.
- **Add-friend** — glass search field; results; send-request / invite states.
- **Friend-detail** — glass balance hero; activity/expense history; settle-up entry.
- **Settle-up** — glass amount card; confirm/mark-as-paid; pending-confirmation state.
- **Notifications** — glass list; pending friend requests with accept/decline.

Every screen must implement **loading (skeleton), empty, and error** states, not just the success state.

## 10. Accessibility

- WCAG AA contrast for all text over glass in BOTH modes and in the solid fallback. Small money labels over translucent surfaces are the highest risk — verify each pair; if a token fails, strengthen text weight/opacity or add a subtle solid backing.
- Reduce transparency → solid fills (§4).
- Reduce motion → all §6 motion disabled.
- Dynamic type: use theme text styles; avoid fixed heights that clip enlarged text.
- Touch targets ≥ 48; semantic labels on icon-only controls.

## 11. Implementation notes

- `MaterialApp`: `theme: AppTheme.light, darkTheme: AppTheme.dark, themeMode: ThemeMode.system`.
- Fonts bundled under `assets/fonts/` and declared in `pubspec.yaml`.
- Tokens via `GlassTokens` `ThemeExtension`; never hardcode colors in screens.
- No changes to `repositories/`, models, or Supabase SQL.

## 12. Phasing (input to the implementation plan)

- **Phase 1 — Foundation.** Fonts + pubspec; `GlassTokens` extension; light + dark themes; primitives (`GlassBackground`, `GlassSurface`, `GlassCard`, `GlassButton`, `GlassScaffold`, `GlassAppBar`, `SkeletonLoader`); reduced-transparency + reduced-motion plumbing. Validate on Home.
- **Phase 2 — Navigation shell.** `HomeShell` + `GlassNavDock` + `IndexedStack`; new Friends, Groups, Activity, Profile tab screens; rework Home into overview; wire `RootScreen` → `HomeShell`.
- **Phase 3 — Restyle remaining screens.** Add-expense, expense-detail, group-detail, create-group, add-friend, friend-detail, settle-up, notifications, sign-in, profile-setup — each with full loading/empty/error states.
- **Phase 4 — Polish.** Motion, accessibility + contrast audit, both-mode QA, blur-perf pass on lower-end devices.

## 13. Out of scope / non-goals

- No backend, data-model, repository, or Supabase-logic changes.
- No new features beyond the 4 nav tab screens the dock requires.
- No cat mascot or illustrations.

## 14. Risks / open items

- **Blur perf** on lower-end Android → bounded blur count + list-level glass (§4); verify in Phase 4.
- **`MediaQueryData.reduceTransparency`** availability varies by Flutter version → confirm at implementation; always ship the in-app setting as the reliable path.
- **Contrast** of green/red and muted text on translucent surfaces → verify per token in Phase 4.
- **Font licensing** — Onest + Space Grotesk are SIL OFL; bundling is permitted.
