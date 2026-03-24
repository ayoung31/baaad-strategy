# Catan Rules Reference

## Overview

Catan is a 3–4 player strategy board game where players colonize the island of Catan by collecting resources, building roads/settlements/cities, and trading. The first player to reach **10 Victory Points (VP)** on their turn wins.

---

## The Board

### Terrain Hexes (19 total)

| Terrain     | Resource | Count |
|-------------|----------|-------|
| Forest      | Lumber   | 4     |
| Hills       | Brick    | 3     |
| Pasture     | Wool     | 4     |
| Fields      | Grain    | 4     |
| Mountains   | Ore      | 3     |
| Desert      | (none)   | 1     |

Note: Brick and Ore are scarcer (3 hexes each) than Lumber, Wool, and Grain (4 hexes each).

### Number Tokens

Placed on each non-desert hex. The number of dots (pips) indicates probability of being rolled on 2d6:

| Number | Pips | Combinations |
|--------|------|--------------|
| 2      | 1    | 1/36         |
| 3      | 2    | 2/36         |
| 4      | 3    | 3/36         |
| 5      | 4    | 4/36         |
| 6      | 5    | 5/36         |
| 8      | 5    | 5/36         |
| 9      | 4    | 4/36         |
| 10     | 3    | 3/36         |
| 11     | 2    | 2/36         |
| 12     | 1    | 1/36         |

(7 is not a token — it triggers the robber)

Two tokens each of 3–11, one each of 2 and 12.

### Ports (9 total)

| Port Type      | Trade Rate | Count |
|----------------|-----------|-------|
| 3:1 General    | 3:1 any   | 4     |
| 2:1 Lumber     | 2:1 wood  | 1     |
| 2:1 Brick      | 2:1 brick | 1     |
| 2:1 Wool       | 2:1 wool  | 1     |
| 2:1 Grain      | 2:1 grain | 1     |
| 2:1 Ore        | 2:1 ore   | 1     |

---

## Setup

1. Assemble the board (fixed or random hex placement).
2. Place number tokens on non-desert hexes.
3. Place ports around the coast.
4. **Initial placement (reverse snake draft):**
   - In turn order, each player places 1 settlement + 1 road.
   - Then in reverse order, each player places a second settlement + road.
   - The second settlement's adjacent hexes grant 1 resource card each at game start.
5. Place the robber on the desert.

---

## Turn Structure

Each turn has three phases:

### 1. Resource Production
- Roll 2d6.
- Every terrain hex matching the rolled number produces resources.
- Each settlement adjacent to that hex yields **1 resource card**; each city yields **2 resource cards**.
- **On a roll of 7:** No resources produced. Instead:
  - Any player holding **more than 7 resource cards** must discard half (rounded down).
  - The active player moves the robber to any terrain hex. No resources are produced from that hex until the robber moves again.
  - The active player may steal 1 random resource from any player with a settlement/city adjacent to the robber's new location.

### 2. Trade
- **Domestic trade:** Negotiate and exchange resource cards freely with other players.
- **Maritime trade (bank):**
  - Default rate: 4:1 (any 4 identical resources for 1 of any resource).
  - With a 3:1 port: 3:1 (any 3 identical resources for 1 of any).
  - With a 2:1 resource port: 2 of the matching resource for 1 of any.
  - Must have a settlement or city on the port's intersection to use it.

### 3. Build
Pay resource cards to build. Multiple builds per turn are allowed.

| Item            | Cost                              | VP  |
|-----------------|-----------------------------------|-----|
| Road            | 1 Lumber + 1 Brick                | 0   |
| Settlement      | 1 Lumber + 1 Brick + 1 Wool + 1 Grain | 1   |
| City (upgrade)  | 3 Ore + 2 Grain                   | +1 (replaces settlement) |
| Development Card| 1 Ore + 1 Wool + 1 Grain         | varies |

**Limits:** 5 settlements, 4 cities, 15 roads per player.

**Settlement placement rules:**
- Must be placed on an unoccupied intersection.
- Must be connected by your road (except initial placement).
- Must be at least 2 road segments away from any other settlement or city (the "distance rule").

---

## Development Cards (25 total)

| Card           | Count | Effect |
|----------------|-------|--------|
| Knight         | 14    | Move the robber; steal 1 resource from an adjacent player |
| Road Building  | 2     | Place 2 free roads |
| Year of Plenty | 2     | Take any 2 resource cards from the bank |
| Monopoly       | 2     | Name a resource; all other players give you all of that resource |
| Victory Point  | 5     | +1 VP (kept secret until win condition) |

**Rules:**
- Draw from the top of a shuffled face-down deck.
- May not play the turn it was purchased.
- Only 1 development card may be played per turn (before or after rolling).
- VP cards are revealed only when claiming victory.

---

## Special Cards

### Largest Army
- Awarded to the first player to play **3 Knight cards**.
- Worth **2 VP**.
- Stolen by any player who surpasses the current holder's knight count.

### Longest Road
- Awarded to the first player to build a continuous road of **at least 5 segments**.
- Worth **2 VP**.
- Stolen by any player who builds a longer road.
- An opponent's settlement/city placed on a road intersection **breaks** that road for Longest Road calculation.

---

## Victory Points Summary

| Source                  | VP  |
|-------------------------|-----|
| Settlement              | 1   |
| City                    | 2   |
| Largest Army            | 2   |
| Longest Road            | 2   |
| Victory Point dev card  | 1 each |

**First player to reach 10 VP on their own turn wins.**

---

## Key Strategic Notes

- **Ore + Grain** are the most important late-game resources: cities (3 Ore + 2 Grain) double production and are worth 2 VP each.
- **Wool (Sheep)** is needed for settlements and dev cards but is the least uniquely powerful resource — it cannot buy cities alone and is the most abundant resource (4 hexes).
- **Brick + Lumber** are critical early for roads and settlements but become less relevant late game.
- **6 and 8** are the highest-probability numbers (5/36 each) and are the most contested spots.
- The robber (7, most probable single outcome at 6/36) is a major disruption tool, especially against players holding many cards.
