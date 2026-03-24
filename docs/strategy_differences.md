# Strategy Differences: balanced, sheep, ore_grain

## Overview

All three strategies share the same simulation framework and interface, but differ in how they score settlement locations, route roads, play dev cards, trade resources, and prioritise building actions. The table below summarises the key axes of difference; the sections that follow explain each in detail.

| Dimension | balanced | sheep | ore_grain |
|---|---|---|---|
| Placement goal | Max production + diversity | Max wool pips | Max ore+grain pips |
| Road routing target | Best diversity spot | 2:1 Wool port | 2:1 Ore or Grain port |
| Dev card trigger | Knights ≥ 2 | Knights ≥ 2 | Knights ≥ 2 |
| Trade order | city→settlement→dev\_card→road | city→settlement→dev\_card→road | city→settlement→dev\_card→road |
| Build priority | City first | Dev card / settlement first | City first |
| Settlement cap | 5 (piece limit) | 5 (piece limit) | 4 (explicit cap) |
| Why it wins/loses | Flexible, no blind spots | Wool can't fund cities | Ore scarcity creates compounding city advantage |

---

## Placement Scoring

### balanced

```
score = pip_sum + diversity_weight × distinct_resource_types
```

Rewards both raw expected production and resource variety. An intersection adjacent to a 5-pip wool, a 5-pip ore, and a 4-pip grain scores higher than a triple-wool 5+5+5 intersection because it covers more resource types. Both placements use the same formula; the diversity term naturally steers the second pick away from resource types already covered by the first.

### sheep

```
score = wool_pips × 2 + total_pips × 0.5
```

Heavily weights wool production. `total_pips × 0.5` is a weak tiebreaker that prevents picking zero-pip wool spots. Non-wool resources are largely ignored in placement scoring.

### ore_grain

```
score = (ore_pips + grain_pips) × 2 + total_pips × 1.0
```

Heavily weights ore and grain. `total_weight = 1.0` (higher than sheep's 0.5) keeps spots with some lumber or brick alongside ore/grain competitive, preventing purely isolated ore/grain placements that leave the player with no infrastructure.

---

## Second Placement — Infrastructure Guard

Both sheep and ore_grain apply an infrastructure guard on their reverse-pass (second) settlement pick. Balanced does not need one because its diversity scoring naturally avoids resource-isolated placements.

**Logic (shared between sheep and ore_grain):**

1. Check what resources the first settlement covers.
2. If **lumber and brick are not both covered** (`has_lb = FALSE`):
   - Filter candidates to those providing at least one missing infra resource (lumber, brick).
   - Prefer candidates covering **both**; fall back to at least one; fall back to all if none exist.
   - Score the filtered set with gap-aware scoring. No port bonus applied.
3. If **lumber and brick are both covered** (`has_lb = TRUE`):
   - Apply full gap-aware scoring plus a port bonus (see below).

The guard ensures the combined initial two settlements always cover at least one infrastructure resource, preventing the player from being permanently unable to build roads or settlements.

**Port bonuses when `has_lb = TRUE`:**

| Strategy | Port bonus |
|---|---|
| sheep | +100 to Wool port intersections (hard target) |
| ore_grain | +50 to Ore or Grain port intersections |

---

## Road Routing

### balanced

Routes toward the highest diversity-scoring unoccupied intersection reachable from the current network. No port targeting. During normal play, only builds a road if it opens a settlement spot not currently adjacent to the road network.

### sheep

Actively pursues the 2:1 Wool port:

- Until a Wool port intersection is settled: routes toward `nearest_wool_port_intersection()`, the closest Wool port intersection by BFS distance from the player's current network.
- Once the Wool port is secured: routes toward the best remaining wool-scoring unoccupied intersection.

During normal play, builds roads freely toward the port regardless of whether the endpoint is immediately settleable.

### ore_grain

Mirrors sheep's logic but targets ore/grain ports:

- Until an Ore or Grain port intersection is settled: routes toward `nearest_og_port_intersection()`, the closest 2:1 Ore or Grain port intersection.
- Once the port is secured: routes toward the best remaining ore+grain-scoring unoccupied intersection.
- During normal play, only builds roads when `settlement_count < 4` (its explicit settlement cap).

---

## Dev Card Play

All three strategies use the same gating rule: **play a Knight only when `knights_played >= 2`** (close to the Largest Army threshold). Knights are held until they are strategically meaningful rather than played opportunistically.

Year of Plenty and Monopoly differ by strategy:

| Card | balanced | sheep | ore_grain |
|---|---|---|---|
| Year of Plenty | Take the 2 resources most needed for the next city | Take ore + grain (fuel for dev card purchases) | Take the 2 resources most needed for the next city |
| Monopoly | Steal the resource with the largest gap vs. city cost | Always steal ore (scarcest resource for sheep) | Steal the resource with the largest gap vs. city cost |

---

## Trading

All three strategies use **simulate-then-commit**: `trade_toward(goal)` simulates the full trade sequence to see whether affordability can be reached; only if it can is the first individual trade action returned. This prevents wasteful partial trades that deplete resources without ever reaching the target cost.

**Trade goal order (identical across all three strategies):**

```
city → settlement → dev_card → road
```

The order is the same, but what fires in practice differs by resource profile:

| Strategy | Typical outcome |
|---|---|
| balanced | City fires regularly (produces ore+grain). Settlement is a common fallback. Road rarely needed. |
| sheep | City almost never fires (no ore/grain production). Settlement fires when sheep has ≥5 wool to trade 4:1 for grain. Road rarely needed (sheep produces lumber+brick naturally). |
| ore_grain | City fires regularly (core production). Settlement fires when city is blocked. Road fires on brick-less boards to enable port access. |

**Gate conditions:**

| Goal | Skip condition |
|---|---|
| city | No settlements to upgrade |
| dev_card | Deck is empty |
| road | `settlement_count ≥ 4` (ore_grain) or `settlement_count ≥ PIECE_LIMITS[["settlement"]]` (balanced, sheep) |

---

## Build Priority (`choose_action`)

All strategies enter **closing mode** (`closing_action`) when `compute_vp(player) >= 5`, switching to a uniform flexible priority regardless of strategy identity. Below 5 VP, each strategy follows its own priority list.

### balanced

1. Play dev card (Knight if ≥2 played; Year of Plenty toward city; Monopoly for largest city gap)
2. Trade (city → settlement → dev\_card → road)
3. Build city (upgrade highest-scoring settlement)
4. Build settlement (best reachable valid spot, gap-aware scoring)
5. Buy dev card
6. Build road — **only if it opens a new settlement spot** not currently reachable
7. Done

### sheep

1. Play dev card (Knight if ≥2 played; Year of Plenty for ore+grain; Monopoly for ore)
2. Trade (city → settlement → dev\_card → road)
3. Buy dev card
4. Build settlement (gap-aware scoring on reachable valid spots)
5. Build city (lower priority — resource starvation is the intended failure mode)
6. Build road toward Wool port (if not secured) or next best wool spot
7. Done

Key difference from balanced: **dev card purchase is step 3** (before settlement), reflecting sheep's bet on Largest Army as a VP path. City is deliberately deprioritised to expose the ore/grain starvation failure mode naturally rather than forcing trades to fix it.

### ore_grain

1. Play dev card (same logic as balanced)
2. Trade (city → settlement → dev\_card → road)
3. Build city (top priority — the entire strategy)
4. Build settlement — **capped at 4 total structures** (settlements + cities combined)
5. Buy dev card (only when city and settlement are both out of reach)
6. Build road — only when `settlement_count < 4` and the target is not yet reachable
7. Done

Key difference from balanced: **explicit settlement cap of 4** keeps resources focused on city upgrades rather than spreading across 5 settlements. Cities at 4 structures alone can reach 8 VP (4 cities × 2), needing only 2 more from dev cards to close out.

---

## Late Game — Closing Action (VP ≥ 5)

All three strategies delegate to the shared `closing_action` routine, which drops specialisation and optimises purely for reaching 10 VP:

1. Play dev card (if clearly beneficial)
2. Trade toward city → settlement → dev\_card
3. Build city
4. Build settlement
5. Buy dev card
6. Build road
7. Done

Each strategy still uses its own `score_fn` to evaluate **which** intersection to settle or upgrade, so placement preferences remain coherent even though the build priority becomes uniform.

---

## Why Each Strategy Wins or Loses

### balanced — consistent performer

No single-resource dependency and no port commitment means balanced is never structurally blocked. Diversity scoring finds spots with good all-round production, trading smooths shortfalls, and the city-first build priority captures the best VP-per-resource conversion. It wins by not making any catastrophic bets.

### sheep — intentional failure mode

Wool is the most abundant resource (4 hexes) so opponents produce it freely without needing the Wool port. Dev card VP is unreliable compared to cities. Sheep's ore/grain production is typically weak or absent, so it cannot fund cities or efficiently buy dev cards without extensive 4:1 trading. Roads toward the Wool port consume lumber+brick that could fund settlements, and the port payoff (2:1 wool) rarely translates into enough ore+grain to win. Sheep demonstrates that over-investing in one abundant resource is a losing strategy.

### ore_grain — strong specialist

Ore is scarce (3 hexes) so securing ore production early creates a supply advantage opponents cannot easily replicate. Cities double output on already-high-value ore/grain hexes, creating compounding VP growth. The 2:1 Ore or Grain port further accelerates city funding. The settlement cap at 4 prevents resource dilution across too many settlements, keeping the focus on upgrading. Ore_grain wins by converting resource efficiency into VP faster than opponents can respond.
