# Pet / coin / mood companion system — design

Revises sub-project 2 from `docs/superpowers/milestones.md`. The original
brief tied coin-earning to expense logging and mood-decay to unpaid
balances; both were rejected during brainstorming (rewarding "logging an
expense" isn't a virtue worth celebrating, and tying the cat's mood to debt
status turns the pet into a guilt trip). This spec replaces both mechanics.

Unchanged from the original brief: one personal pet per user, follows them
across all groups (no shared/per-group pet). Coins are never purchasable
with real money, and cosmetics never affect gameplay.

## 1. Coin economy

A single currency, earned only through the actions below. Coins are never
earned by logging/creating expenses — that's data entry, not a rewarded
behavior. Coins are spent only in the (TBD, see Open Questions) shop.

| Action | Cost to user | Coin reward | Frequency limit |
|---|---|---|---|
| Daily check-in | Free | +5 | Once per day |
| Feed | Free | +2 per feed | Once per 3 hours (≈8 feeds/day max) |
| Feed streak — fed every day for 7 consecutive days | — | +10 bonus | Once per completed streak week |
| Pet | Free | 0 (mood only, no coins) | Unbounded (see Open Questions) |
| Settle up (full settlement of a balance) | — | +20 | Per settlement |

Rationale: settling up is the one real "virtue" worth a large reward
(+20, the single biggest payout), but it's infrequent, so check-in/feed
give small frequent trickles that keep the loop alive between settlements.

## 2. Mood system — decoupled from money

Mood reflects care-action engagement only (feeding/petting cadence) and is
**not** affected by debts, balances, or settle-up promptness in any way. A
user who owes money but visits and cares for the cat daily has a happy cat.
This is a deliberate reversal of the original brief, which tied mood dips to
unpaid balances (7+ days unpaid, backlog dumping, owed money with no
settle-up ask) — that logic made the pet feel like a nag about the user's
debts rather than a companion.

Mood is purely visual — it never affects coin earning or spending.

The exact decay/recovery curve (how fast mood drops on neglect, how fast it
recovers on renewed care) is an open question, carried over from the
original brief.

## 3. Coin sink (shop) — deferred

What coins actually buy is not decided in this spec. Cosmetics requiring
new art per combination (skins/outfits on the cat) were flagged as hard to
implement, since the app currently has a single static cat image and
dynamically rendering new combinations would need real art production.
Candidate directions discussed but not committed to:

- Color/fur tint filters over the existing cat image (no new art, code-only)
- Background/room theme swaps behind the cat (cat art untouched)
- Props placed beside (not on) the cat — bowl, toy, blanket
- Non-visual sinks — nicknames, streak-savers, badges

This is tracked as a follow-up decision, not a blocker for the rest of this
spec.

## 4. Monetization

Pro subscription unlocks an exclusive cosmetics catalog, consistent with
the existing monetization draft (sub-project 4 in `milestones.md`). No
pay-to-earn-coins mechanic, no gameplay-affecting purchases of any kind —
matches the original brief's constraint.

## Open questions (parked, not blocking implementation of the core loop)

- What coins actually buy (resolved when sub-project 6, Cosmetics store, or
  a dedicated follow-up spec picks this up)
- Mood decay/recovery curve specifics (rate of decline on neglect, rate of
  recovery on renewed care)
- Whether petting needs a frequency limit or diminishing returns, or can
  stay unbounded since it grants no coins
