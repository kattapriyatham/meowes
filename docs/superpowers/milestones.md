# Meowes — Milestones

Sub-project roadmap for the full Meowes app brief (Splitwise-style expense
splitting + a personal cat companion tied to settle-up/logging behavior).
Each sub-project gets its own brainstorm → spec → plan → implementation
cycle before work starts. This doc tracks status only — the detailed specs
and plans live in `docs/superpowers/specs/` and `docs/superpowers/plans/`.

## 1. Core expense splitting — ✅ Complete

Auth, friends, groups, expenses, equal/percentage/exact splits, server-side
balance computation (pairwise + group debt simplification), two-sided
settle-up confirmation, and the screens tying it together.

- Spec: `docs/superpowers/specs/2026-07-27-core-expense-splitting-design.md`
- Plan: `docs/superpowers/plans/2026-07-27-core-expense-splitting.md`
- Known gaps / follow-ups: `docs/superpowers/known-issues.md`

## 2. Pet / coin / mood companion system — Design revised, not started

The actual product differentiator. Original brief tied coin-earning to
expense logging and mood to unpaid balances; both were reworked during
brainstorming (rewarding expense logging isn't a virtue, and tying mood to
debt status turned the pet into a guilt trip). Current design:

- One personal pet per user, follows them across all groups (no shared pet).
- Coin earning: daily check-in (+5), feed (+2 per feed, once per 3h), feed
  streak of 7 consecutive days (+10 bonus), settle a balance in full (+20).
  Never earned by logging expenses.
- Mood (visual only, decoupled from money/debts entirely): reflects
  feeding/petting engagement cadence, not balances or settle-up promptness.
- Coin spending: Activities & Memories. Coins buy handcrafted activities
  (pre-generated illustration + fixed caption, e.g. "Park Picnic"), each
  producing a permanent memory in the cat's journal. 3-5 activities
  rotate at a time; unlocked memories stay forever. Sidesteps the
  dynamic-cosmetics-art problem since nothing is rendered at runtime.
  Explicitly excludes wearables/decor/furniture/stat buffs.
- Monetization: open — the earlier "Pro = cosmetics" plan no longer
  applies since cosmetics are out of scope; how Pro hooks into Activities
  & Memories is deferred to sub-project 4.
- Open questions: exact mood decay/recovery curve, monetization hook,
  whether petting needs a frequency limit, activity rotation mechanics.

- Spec: `docs/superpowers/specs/2026-07-29-pet-coin-mood-companion-design.md`

## 3. UPI-native settle-up — Not started

Deep link to GPay/PhonePe pre-filled with amount and payee. Core India
differentiator; needs early technical validation per the brief. Builds on
top of the existing `SettlementRepository`/settle-up flow from sub-project 1.

## 4. Monetization — Not started

- **Pro subscription** (primary revenue): UPI settle-up, unlimited groups,
  receipt OCR, currency conversion, spending charts, expanded cosmetics.
  Target ~$2.99/mo, ~₹999/yr.
- **Lifetime** option (one-time), mirrors the anti-subscription-fatigue
  pattern from the brief's Cat on Chair reference case.
- **Group pass**: one purchase unlocks Pro for the whole group, priced
  ~2–2.5x individual Pro (Spotify Family–style math).
- **Free tier**: unlimited logging/splits/debt simplification, capped at
  ~2 active groups (brief flags this number as needing validation), full
  core companion loop with one base skin, ad-free.
- Tooling: RevenueCat for paywall/subscription management.
- Explicitly excluded per the brief: ads, selling spending data, coins
  purchasable with real money.

## 5. Receipt OCR, currency conversion, spending charts — Not started

Pro-tier features bundled with monetization (sub-project 4) but distinct
enough in scope to warrant their own spec/plan when picked up.

## 6. Cosmetics store — Not started

Cat skins, room decor, backgrounds — à la carte or bundled in Pro. Depends
on sub-project 2 (pet system) existing first.

---

## Also outside these sub-projects (ops/launch, not app features)

Per the original brief's "What Launch Actually Requires" section — not
sub-projects with their own screens, but real launch blockers when the time
comes: illustrator/art direction for the pet's visual style, Apple/Google
developer accounts, privacy policy + terms of service, ASO tooling, a
beta-testing group, and app store listing assets.
