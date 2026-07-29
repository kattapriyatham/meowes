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

## 3. Coin sink — Activities & Memories

Resolves the earlier "what do coins buy" open question. Coins are spent on
**Activities** — time spent with the companion cat. Each activity produces
a permanent **Memory**: a pre-generated illustration plus a short caption,
never a wearable, room decoration, or stat boost. This sidesteps the
dynamic-art-rendering problem entirely, since every activity is handcrafted
(fixed art + fixed caption) rather than composed at runtime from
combinable pieces.

**Design principles**
- Activities are the primary (only) coin sink.
- Activities are optional and never affect expense-sharing functionality.
- No gameplay advantages or stat boosts, no real-money coin purchases.
- Every activity uses pre-generated artwork and predefined captions —
  nothing rendered dynamically.
- Activities create lasting memories rather than consumable items.

**User flow**
1. User earns coins through the mechanics in Section 1.
2. User opens the Activities section from the pet card.
3. A small set of available activities is displayed.
4. User selects an activity and spends the required coins.
5. The activity plays immediately (or after a short animation).
6. A memory is added to the cat's journal.

**Activity structure** — each activity has a name, coin cost, illustration
(pre-generated asset), short caption, and category.

Example — *Park Picnic*: 60 coins, category Outdoors, image
`park_picnic_01.webp`, caption "We spent the afternoon under a big tree. I
almost stole your sandwich."

**Categories**: Walks, Relaxation, Grooming, Outdoor Adventures, Seasonal
Events, Funny Moments, Special Occasions. Examples: Morning Walk, Park
Picnic, Spa Day, Beach Trip, Watching the Rain, Camping, Birthday
Celebration, Chased a Butterfly.

**Availability**: only 3–5 activities available at a time, rotating
periodically (e.g. daily) to keep the experience fresh. Previously
unlocked memories remain permanently accessible regardless of rotation.

**Memory journal**: every completed activity is stored in a chronological
journal. Each memory entry contains the activity image, name, caption, and
completion date. The journal is the history of the companion's life and
serves as the long-term progression system (in place of
growth/evolution milestones, which were dropped earlier in this
brainstorm).

**Economy guidelines**
- Low-tier: 20–50 coins
- Mid-tier: 60–150 coins
- Premium: 200–500 coins
- Seasonal/milestone: 500+ coins

Coins are never required for basic pet interactions (feeding, petting) —
those stay free per Section 1.

**Future extensions** (not in scope now): seasonal activity rotations,
limited-time festival activities, group milestone activities (shared
unlocks after group achievements), achievement rewards for completing
activity collections, personality-based captions for the same activity.

**Out of scope**: room decoration, wearable cosmetics, furniture, pet
stats/gameplay buffs, coin purchases with real money, user-generated
customization.

## 4. Monetization

Open. The earlier plan ("Pro unlocks an exclusive cosmetics catalog") no
longer applies, since cosmetics/wearables/decor are explicitly out of
scope for Activities & Memories. How Pro/monetization hooks into this
system — exclusive premium activities, more activity slots, faster
rotation, journal perks, or something else — is deferred to the dedicated
monetization sub-project (#4 in `milestones.md`).

## Open questions (parked, not blocking implementation of the core loop)

- Monetization hook for Activities & Memories (see Section 4)
- Mood decay/recovery curve specifics (rate of decline on neglect, rate of
  recovery on renewed care)
- Whether petting needs a frequency limit or diminishing returns, or can
  stay unbounded since it grants no coins
- Exact activity rotation mechanics (per-user vs. global, rotation cadence
  beyond "e.g. daily")
