# board.R — Full Implementation Reference

## Purpose

`board.R` defines all data structures and functions needed to represent, generate, and query a Catan board. It is the lowest-level module in the simulation — all other modules (`game.R`, `strategy.R`, etc.) consume the board object it produces but never modify the board representation themselves except through the mutation helpers defined here.

---

## Data Structures

### Board Object

The top-level object returned by `generate_board()`. A plain R named list:

```r
list(
  hexes         = list(...),  # 19 hex objects
  intersections = list(...),  # 54 intersection objects
  edges         = list(...),  # ~72 edge objects
  robber_hex    = <int>       # hex ID currently holding the robber
)
```

### Hex Object

Created by `make_hex(id, terrain, token)`:

| Field        | Type      | Description |
|--------------|-----------|-------------|
| `id`         | integer   | Hex index 1–19 |
| `terrain`    | character | `"forest"`, `"hills"`, `"pasture"`, `"fields"`, `"mountain"`, or `"desert"` |
| `resource`   | character | Resource produced (`NA` for desert) |
| `token`      | integer   | Number token (2–12, `NA` for desert) |
| `pips`       | integer   | Dice probability weight (0–5) |
| `has_robber` | logical   | Whether the robber is currently here |

### Intersection Object

Created by `make_intersection(id)`:

| Field       | Type      | Description |
|-------------|-----------|-------------|
| `id`        | integer   | Intersection index 1–54 |
| `owner`     | integer   | Player index who owns a settlement/city here (`NA` if empty) |
| `structure` | character | `"none"`, `"settlement"`, or `"city"` |
| `port`      | list/NULL | Port object if this intersection borders a port, otherwise `NULL` |
| `is_coastal`| logical   | Whether this intersection is on the board edge |

**Port sub-object** (attached to `intersection$port`):

| Field      | Type      | Description |
|------------|-----------|-------------|
| `resource` | character | Resource the port specialises in (`NA` = general 3:1 port) |
| `rate`     | integer   | How many of `resource` to give for 1 resource of any type |

### Edge Object

Created by `make_edge(id, i, j)`:

| Field   | Type    | Description |
|---------|---------|-------------|
| `id`    | integer | Edge index  |
| `ends`  | integer[2] | The two intersection IDs this road segment connects |
| `owner` | integer | Player index who has placed a road here (`NA` if empty) |

---

## Constants

| Constant                 | Description |
|--------------------------|-------------|
| `PIPS`                   | Named integer vector mapping token values 2–12 (excl. 7) to dice probability counts (1–5) |
| `RESOURCES`              | Character vector of the five resource names |
| `TERRAIN_COUNTS`         | Named integer vector: how many hexes of each terrain type appear on a standard board |
| `TERRAIN_RESOURCE`       | Named character vector mapping each terrain to the resource it produces |
| `NUMBER_TOKENS`          | Integer vector of all 18 tokens placed on non-desert hexes |
| `PORT_SIDE_TEMPLATES`    | List of 6 side templates; see Port System section below |
| `HEX_INTERSECTIONS`      | List of length 19; each element is an integer vector of the 6 intersection IDs surrounding that hex |
| `INTERSECTION_ADJACENCY` | List of length 54; each element is the integer vector of intersection IDs directly connected by a road edge |
| `COASTAL_INTERSECTIONS`  | Integer vector of the 30 intersection IDs on the board perimeter, in clockwise order |
| `BOARD_SIDES`            | List of 6 vectors (6 intersection IDs each) representing the 6 physical sides of the board hexagon |

---

## Board Geometry Notes

The standard Catan board has:
- **19 hexes** arranged in a 3-4-5-4-3 row layout
- **54 intersections** (vertices of the hex grid)
- **72 edges** (sides of the hex grid)
- **30 coastal intersections** forming the board perimeter

Intersections are numbered 1–54 across 12 horizontal levels, left to right within each level:

| Level | y-coord | Count | Description |
|-------|---------|-------|-------------|
| 1  | −1   | 3  | Top points of row-1 hexes (IDs 1–3) |
| 2  | −½   | 4  | Upper side vertices of row-1 (IDs 4–7) |
| 3  | +½   | 4  | Lower side of row-1 / N of row-2 (IDs 8–11) |
| 4  | +1   | 5  | S of row-1 / NW–NE shared in row-2 (IDs 12–16) |
| 5  | +2   | 5  | SE–SW of row-2 / N of row-3 (IDs 17–21) |
| 6  | +5/2 | 6  | Upper side vertices of row-3 (IDs 22–27) |
| 7  | +7/2 | 6  | Lower side vertices of row-3 (IDs 28–33) |
| 8  | +4   | 5  | S of row-3 / NW–NE shared in row-4 (IDs 34–38) |
| 9  | +5   | 5  | SE–SW of row-4 / N of row-5 (IDs 39–43) |
| 10 | +11/2| 4  | Upper side vertices of row-5 (IDs 44–47) |
| 11 | +13/2| 4  | Lower side vertices of row-5 (IDs 48–51) |
| 12 | +7   | 3  | Bottom points of row-5 hexes (IDs 52–54) |

Total: 3+4+4+5+5+6+6+5+5+4+4+3 = **54** ✓

Each hex's 6 intersections are stored in clockwise order starting from the top (N, NE, SE, S, SW, NW).

`INTERSECTION_ADJACENCY` is derived automatically by `build_intersection_adjacency()` at load time, scanning `HEX_INTERSECTIONS` for all consecutive pairs around each hex ring. All IDs are guaranteed in range 1–54.

---

## Port System

### Physical structure

The board's outer perimeter is a hexagon with **6 sides**. Each side spans 5 coastal edges (the outer edges of the border hexes along that face). Consecutive sides share one corner intersection, so:

```
6 sides × 6 intersections − 6 shared corners = 30 unique coastal intersections  ✓
6 sides × 5 edges                             = 30 coastal edges                ✓
```

`BOARD_SIDES` is a list of 6 vectors, each containing 6 coastal intersection IDs in clockwise order along that side. It is derived from `COASTAL_INTERSECTIONS` using overlapping windows of size 6 with a stride of 5:

| Side | Intersections | Physical face |
|------|---------------|---------------|
| 1 | 1, 5, 2, 6, 3, 7 | Top |
| 2 | 7, 11, 16, 21, 27, 33 | Upper-right |
| 3 | 33, 38, 43, 47, 51, 54 | Lower-right |
| 4 | 54, 50, 53, 49, 52, 48 | Bottom |
| 5 | 48, 44, 39, 34, 28, 22 | Lower-left |
| 6 | 22, 17, 12, 8, 4, 1 | Upper-left |

### Port side templates

Each of the 6 `PORT_SIDE_TEMPLATES` defines which of the 5 edge slots on a side carry a port. `NULL` means a blank coastal edge; a port list means a port occupies that edge.

| Template | Edge 1 | Edge 2 | Edge 3 | Edge 4 | Edge 5 |
|----------|--------|--------|--------|--------|--------|
| A        | 3:1    | —      | —      | brick  | —      |
| B        | —      | —      | lumber | —      | —      |
| C        | 3:1    | —      | —      | grain  | —      |
| D        | —      | —      | ore    | —      | —      |
| E        | 3:1    | —      | —      | wool   | —      |
| F        | —      | —      | 3:1    | —      | —      |

Total ports: 4 × general (3:1) + brick + lumber + grain + ore + wool = **9 ports** ✓

### Random assignment

During `assign_ports()`, the 6 templates are shuffled and each is assigned to one of the 6 physical board sides. This randomises which face of the board carries which port combination every game, matching standard Catan rules.

---

## Functions

### Board Generation

---

#### `generate_board(random_terrain, random_tokens, random_ports, seed)`

The primary entry point. Builds a complete board ready for a game.

**Parameters:**

| Name             | Type    | Default | Description |
|------------------|---------|---------|-------------|
| `random_terrain` | logical | `TRUE`  | Shuffle hex terrain order |
| `random_tokens`  | logical | `TRUE`  | Shuffle number token placement |
| `random_ports`   | logical | `TRUE`  | Randomly assign port-side templates to physical board sides |
| `seed`           | integer | `NULL`  | Optional RNG seed for reproducibility |

**Returns:** A board list (see Board Object above).

**Steps:**
1. Expand `TERRAIN_COUNTS` into a length-19 terrain sequence; optionally shuffle.
2. Sample `NUMBER_TOKENS` for random placement; assign one token per non-desert hex in order.
3. Call `make_hex()` for all 19 hexes; desert gets `token = NA`.
4. Call `make_intersection()` for all 54 intersections.
5. Call `assign_ports()` to attach port objects to coastal intersections.
6. Call `build_edges()` to enumerate all road slots.
7. Return the assembled board list with `robber_hex` pointing at the desert.

---

#### `build_intersection_adjacency()`

Scans `HEX_INTERSECTIONS` and records every consecutive pair around each hex ring as a bidirectional edge. Called once at load time; result stored in `INTERSECTION_ADJACENCY`.

**Returns:** List of length 54; each element is an integer vector of neighbour IDs.

---

#### `build_edges()`

Iterates over all pairs `(i, j)` in `INTERSECTION_ADJACENCY` with `j > i` and creates one edge object per pair.

**Returns:** List of edge objects.

---

#### `assign_ports(intersections, shuffle)`

Assigns ports to intersections using the 6-side template system.

1. Optionally shuffles the order of `PORT_SIDE_TEMPLATES` (one permutation = one game's port layout).
2. For each of the 6 physical sides in `BOARD_SIDES`, reads the corresponding (possibly shuffled) template.
3. For each non-`NULL` slot in the template, identifies the two coastal intersections bordering that edge (`side_ints[k]` and `side_ints[k+1]`) and attaches the port object to both.

A player needs a settlement or city on **either** of the two intersections bordering a port edge to access it.

| Parameter      | Type    | Default | Description |
|----------------|---------|---------|-------------|
| `intersections`| list    | —       | List of intersection objects |
| `shuffle`      | logical | `TRUE`  | If `TRUE`, randomly assign templates to sides (standard Catan behaviour) |

**Returns:** Updated intersections list.

---

#### `make_hex(id, terrain, token)`

Constructs a single hex object. Looks up `TERRAIN_RESOURCE` and `PIPS` automatically.

---

#### `make_intersection(id)`

Constructs a single intersection object with all fields initialised to empty/default values.

---

#### `make_edge(id, i, j)`

Constructs a single edge object for the road slot between intersections `i` and `j`.

---

### Query Helpers

---

#### `hexes_at_intersection(board, intersection_id)`

Returns all hex IDs whose corner set includes `intersection_id`. Typically 1–3 hexes.

Used by: `strategy.R` to score an intersection's resource production.

---

#### `intersections_of_hex(hex_id)`

Returns the 6 intersection IDs around a hex directly from `HEX_INTERSECTIONS`.

Used by: `compute_production()` when distributing resources after a roll.

---

#### `adjacent_intersections(intersection_id)`

Returns all intersection IDs one road-edge away from the given intersection, from `INTERSECTION_ADJACENCY`.

Used by: `is_valid_settlement_spot()`, `is_valid_road_spot()`, `longest_road()`.

---

#### `get_edge(board, i, j)`

Linear scan of `board$edges` to find the edge connecting intersections `i` and `j`. Returns the edge object or `NULL`.

---

#### `get_edge_id(board, i, j)`

Same as `get_edge()` but returns the integer edge ID (or `NA_integer_`).

---

#### `best_port_for_player(board, player, resource)`

Checks all intersections in `player$settlement_locations`. Returns the port with the lowest trade rate applicable to `resource` (or the best general port if `resource = NA`). Falls back to `rate = 4` (bank rate) if the player has no relevant port.

**Returns:** Named list `list(resource = ..., rate = ...)`.

---

#### `trade_rate_for(board, player, resource)`

Convenience wrapper around `best_port_for_player()`. Returns just the integer rate (2, 3, or 4).

---

### Placement Validation

---

#### `is_valid_settlement_spot(board, intersection_id)`

Enforces:
- Intersection is currently empty (`structure == "none"`).
- No adjacent intersection holds any structure (distance rule).

Does **not** check road connectivity — that is enforced in `game.R` for non-initial placements.

**Returns:** `TRUE` if legal.

---

#### `is_valid_road_spot(board, edge_id, player_id)`

Enforces:
- Edge is currently empty (`owner == NA`).
- At least one endpoint either (a) has a settlement/city owned by `player_id`, or (b) connects to an adjacent road owned by `player_id`.

**Returns:** `TRUE` if legal.

---

### Board Mutation Helpers

These functions return a **new board** with the modification applied. Board state is never mutated in place, keeping the game loop's state management explicit.

---

#### `place_structure(board, intersection_id, player_id, structure)`

Sets `owner` and `structure` on the target intersection.

| `structure` value | Effect |
|-------------------|--------|
| `"settlement"`    | Initial placement or normal build |
| `"city"`          | Upgrade from settlement |

**Returns:** Updated board.

---

#### `place_road(board, edge_id, player_id)`

Sets `owner` on the target edge.

**Returns:** Updated board.

---

#### `move_robber(board, hex_id)`

Clears `has_robber` on the current robber hex, sets it on `hex_id`, and updates `board$robber_hex`.

**Returns:** Updated board.

---

### Resource Production

---

#### `compute_production(board, roll)`

For a given dice roll, iterates over all hexes whose token matches `roll`. Skips:
- Desert hexes (no resource).
- Hexes blocked by the robber.

For each qualifying hex, iterates its 6 intersections. Any settlement produces 1 resource; any city produces 2.

**Returns:** A `data.frame` with columns:

| Column      | Type    | Description |
|-------------|---------|-------------|
| `player_id` | integer | Player who receives resources |
| `resource`  | character | Resource type |
| `amount`    | integer | Units to add to the player's hand |

Returns a zero-row data frame if no production occurs.

---

### Longest Road

---

#### `longest_road(board, player_id)`

Computes the length of the longest continuous road for `player_id` using depth-first search.

**Algorithm:**
1. Build a road adjacency list restricted to edges owned by `player_id`.
2. For every intersection that has at least one of the player's roads, launch a DFS.
3. DFS tracks **visited edges** (not nodes), so it can pass through the same intersection twice via different roads (correct Catan rule).
4. A path is blocked if it reaches an intersection occupied by an **opponent's** settlement or city.
5. Returns the maximum depth reached across all starting points.

**Returns:** Integer road length.

Note: The 2 VP bonus for Longest Road (≥ 5 segments) is awarded in `game.R`, not here.

---

### Board Summary Utilities

---

#### `board_hex_summary(board)`

Converts the hex list into a tidy `data.frame` for debugging or logging.

**Returns:** data.frame with columns `id`, `terrain`, `resource`, `token`, `pips`, `has_robber`.

---

#### `board_port_summary(board)`

Scans all intersections and collects those with a port attached.

**Returns:** data.frame with columns `intersection_id`, `resource` (`"general"` for 3:1 ports), `rate`.

---

## Interaction with Other Modules

| Caller       | Functions used |
|--------------|----------------|
| `game.R`     | `generate_board()`, `compute_production()`, `place_structure()`, `place_road()`, `move_robber()`, `is_valid_settlement_spot()`, `is_valid_road_spot()`, `longest_road()` |
| `strategy.R` | `hexes_at_intersection()`, `adjacent_intersections()`, `trade_rate_for()`, `best_port_for_player()`, `is_valid_settlement_spot()`, `is_valid_road_spot()`, `board_hex_summary()` |
| `analysis.R` | `board_hex_summary()`, `board_port_summary()` (optional, for diagnostics) |
