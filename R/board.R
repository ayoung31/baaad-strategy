# =============================================================================
# board.R
# Catan board representation and generation.
#
# The Catan board is modelled as three interconnected lookup structures:
#   - hexes:         the 19 terrain tiles (resource, number token, pip count)
#   - intersections: the 54 vertices where settlements/cities are placed
#   - edges:         the 72 road segments connecting adjacent intersections
#
# Ports are attached to specific intersections along the coast.
#
# All board state is stored as a plain R list so it can be passed freely
# between functions without reference semantics complications.
# =============================================================================


# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------

# Pip counts for each number token (how many dice combinations produce it).
# 7 is excluded — it triggers the robber instead of producing resources.
PIPS <- c(
  "2"  = 1,
  "3"  = 2,
  "4"  = 3,
  "5"  = 4,
  "6"  = 5,
  "8"  = 5,
  "9"  = 4,
  "10" = 3,
  "11" = 2,
  "12" = 1
)

# Resource names used throughout the simulation.
RESOURCES <- c("lumber", "brick", "wool", "grain", "ore")

# Standard terrain composition: 19 hexes total.
# Wool/lumber/grain have 4 hexes each; brick/ore have only 3 each (scarcer).
TERRAIN_COUNTS <- c(
  forest   = 4,   # produces lumber
  hills    = 3,   # produces brick
  pasture  = 4,   # produces wool
  fields   = 4,   # produces grain
  mountain = 3,   # produces ore
  desert   = 1    # produces nothing; robber starts here
)

# Mapping from terrain type to resource produced.
TERRAIN_RESOURCE <- c(
  forest   = "lumber",
  hills    = "brick",
  pasture  = "wool",
  fields   = "grain",
  mountain = "ore",
  desert   = NA_character_
)

# Standard number token distribution: two each of 3-11 (excl. 7), one each of
# 2 and 12. This gives 18 tokens for the 18 non-desert hexes.
NUMBER_TOKENS <- c(2L, 3L, 3L, 4L, 4L, 5L, 5L, 6L, 6L, 8L, 8L, 9L, 9L, 10L, 10L, 11L, 11L, 12L)

# Standard token sequence A through R (the number on the face of each lettered
# token, in alphabetical order).  Placing tokens in this order along the spiral
# guarantees no two red numbers (6 or 8) are ever adjacent.
STANDARD_TOKEN_SEQUENCE <- c(5L, 2L, 6L, 3L, 8L, 10L, 9L, 12L, 11L, 4L,
                              8L, 10L, 9L, 4L, 5L, 6L, 3L, 11L)

# Hex IDs visited in counterclockwise spiral order starting from the top-left
# corner hex.  Token letter A is placed on the first non-desert hex in this
# sequence, B on the second, and so on through R.  All 19 positions are listed;
# the desert (wherever it falls in a random layout) is skipped at runtime.
HEX_SPIRAL_ORDER <- c(1L, 4L, 8L, 13L, 17L, 18L, 19L, 16L, 12L, 7L,
                      3L, 2L, 5L, 9L, 14L, 15L, 11L, 6L, 10L)

# -----------------------------------------------------------------------------
# Port side templates.
#
# The Catan board has 6 sides (faces of the outer hexagon). Each side contains
# exactly 5 coastal edges — the slots where a port tile can be placed. The 6
# side templates below define which of those 5 edge slots carry a port and what
# type it is. NULL means the slot is a blank coastal edge with no port.
#
# The 6 templates together account for all 9 ports:
#   4 general (3:1) + brick + lumber + grain + ore + wool (each 2:1).
#
# During board setup the 6 templates are randomly assigned to the 6 physical
# board sides, so port positions differ every game.
# -----------------------------------------------------------------------------

PORT_SIDE_TEMPLATES <- list(
  # Template A: 3:1 on edge 1, brick on edge 4
  list(
    list(resource = NA,       rate = 3),  # edge 1 — general 3:1
    NULL,                                  # edge 2 — blank
    NULL,                                  # edge 3 — blank
    list(resource = "brick",  rate = 2),  # edge 4 — brick 2:1
    NULL                                   # edge 5 — blank
  ),
  # Template B: lumber on edge 3
  list(
    NULL,
    NULL,
    list(resource = "lumber", rate = 2),  # edge 3 — lumber 2:1
    NULL,
    NULL
  ),
  # Template C: 3:1 on edge 1, grain on edge 4
  list(
    list(resource = NA,       rate = 3),  # edge 1 — general 3:1
    NULL,
    NULL,
    list(resource = "grain",  rate = 2),  # edge 4 — grain 2:1
    NULL
  ),
  # Template D: ore on edge 3
  list(
    NULL,
    NULL,
    list(resource = "ore",    rate = 2),  # edge 3 — ore 2:1
    NULL,
    NULL
  ),
  # Template E: 3:1 on edge 1, wool on edge 4
  list(
    list(resource = NA,       rate = 3),  # edge 1 — general 3:1
    NULL,
    NULL,
    list(resource = "wool",   rate = 2),  # edge 4 — wool (sheep) 2:1
    NULL
  ),
  # Template F: 3:1 on edge 3
  list(
    NULL,
    NULL,
    list(resource = NA,       rate = 3),  # edge 3 — general 3:1
    NULL,
    NULL
  )
)

# -----------------------------------------------------------------------------
# Hex adjacency: which intersections border each hex?
#
# The standard Catan board uses pointed-top hexes in a 3-4-5-4-3 row layout.
# Intersections are numbered 1-54 by horizontal level, left to right within
# each level (12 levels total).  The numbering is derived geometrically:
#
#   Level  1 (y= -1  ):  3 vertices — top points of row-1 hexes
#   Level  2 (y= -1/2):  4 vertices — upper side vertices of row-1 hexes
#   Level  3 (y=  1/2):  4 vertices — lower side vertices of row-1 / N of row-2
#   Level  4 (y=  1  ):  5 vertices — S of row-1 / NW-NE shared in row-2
#   Level  5 (y=  2  ):  5 vertices — SE-SW of row-2 / N of row-3
#   Level  6 (y=  5/2):  6 vertices — upper side vertices of row-3
#   Level  7 (y=  7/2):  6 vertices — lower side vertices of row-3
#   Level  8 (y=  4  ):  5 vertices — S of row-3 / NW-NE shared in row-4
#   Level  9 (y=  5  ):  5 vertices — SE-SW of row-4 / N of row-5
#   Level 10 (y= 11/2):  4 vertices — upper side vertices of row-5
#   Level 11 (y= 13/2):  4 vertices — lower side vertices of row-5
#   Level 12 (y=  7  ):  3 vertices — bottom points of row-5 hexes
#
#   Total: 3+4+4+5+5+6+6+5+5+4+4+3 = 54  ✓
#
# Vertices within each level are numbered left to right.
# The full geometric derivation is in docs/function_details/board.md.
# -----------------------------------------------------------------------------

# HEX_INTERSECTIONS[[i]] gives the 6 intersection IDs around hex i in
# clockwise order starting from the top (N, NE, SE, S, SW, NW).
HEX_INTERSECTIONS <- list(
  # Row 1 (3 hexes, left to right)
  c( 1,  5,  9, 13,  8,  4),   # hex 1
  c( 2,  6, 10, 14,  9,  5),   # hex 2
  c( 3,  7, 11, 15, 10,  6),   # hex 3
  # Row 2 (4 hexes, left to right)
  c( 8, 13, 18, 23, 17, 12),   # hex 4
  c( 9, 14, 19, 24, 18, 13),   # hex 5
  c(10, 15, 20, 25, 19, 14),   # hex 6
  c(11, 16, 21, 26, 20, 15),   # hex 7
  # Row 3 (5 hexes, left to right — widest row)
  c(17, 23, 29, 34, 28, 22),   # hex 8
  c(18, 24, 30, 35, 29, 23),   # hex 9
  c(19, 25, 31, 36, 30, 24),   # hex 10
  c(20, 26, 32, 37, 31, 25),   # hex 11
  c(21, 27, 33, 38, 32, 26),   # hex 12
  # Row 4 (4 hexes, left to right)
  c(29, 35, 40, 44, 39, 34),   # hex 13
  c(30, 36, 41, 45, 40, 35),   # hex 14
  c(31, 37, 42, 46, 41, 36),   # hex 15
  c(32, 38, 43, 47, 42, 37),   # hex 16
  # Row 5 (3 hexes, left to right)
  c(40, 45, 49, 52, 48, 44),   # hex 17
  c(41, 46, 50, 53, 49, 45),   # hex 18
  c(42, 47, 51, 54, 50, 46)    # hex 19
)

# -----------------------------------------------------------------------------
# Intersection adjacency: which intersections are connected by an edge?
# Used for road placement validation and Longest Road computation.
# This is derived from the hex adjacency above: two intersections are adjacent
# if they appear together on the same hex and are consecutive in its ring.
# -----------------------------------------------------------------------------

#' Build the intersection adjacency list from HEX_INTERSECTIONS.
#'
#' @return A list of length 54 where element [[i]] is an integer vector of
#'   intersection IDs directly connected to intersection i by a road edge.
build_intersection_adjacency <- function() {
  adj <- vector("list", 54)
  for (i in seq_along(adj)) adj[[i]] <- integer(0)

  for (hex_corners in HEX_INTERSECTIONS) {
    n <- length(hex_corners)
    for (k in seq_len(n)) {
      # Each consecutive pair around the hex ring shares an edge.
      a <- hex_corners[k]
      b <- hex_corners[(k %% n) + 1]
      if (!(b %in% adj[[a]])) adj[[a]] <- c(adj[[a]], b)
      if (!(a %in% adj[[b]])) adj[[b]] <- c(adj[[b]], a)
    }
  }
  adj
}

# Pre-compute once at load time and store as a module-level constant.
INTERSECTION_ADJACENCY <- build_intersection_adjacency()

#' Build the hex adjacency list from HEX_INTERSECTIONS.
#' Two hexes are adjacent iff they share exactly 2 intersection IDs (i.e. share
#' an edge).  Used to validate that red number tokens (6 and 8) are not placed
#' on adjacent hexes.
#'
#' @return A list of length 19 where element [[i]] is an integer vector of hex
#'   IDs that share an edge with hex i.
build_hex_adjacency <- function() {
  adj <- vector("list", 19)
  for (i in seq_along(adj)) adj[[i]] <- integer(0)
  for (h1 in seq_len(18)) {
    for (h2 in (h1 + 1L):19L) {
      if (length(intersect(HEX_INTERSECTIONS[[h1]], HEX_INTERSECTIONS[[h2]])) == 2L) {
        adj[[h1]] <- c(adj[[h1]], h2)
        adj[[h2]] <- c(adj[[h2]], h1)
      }
    }
  }
  adj
}

HEX_ADJACENCY <- build_hex_adjacency()

# Coastal intersection IDs — the 30 intersections that touch the board edge.
# Listed in clockwise order starting from the top-left point (intersection 1).
#
# The perimeter zigzags along the outer boundary of each border hex:
#   Top side    (side 1): 1, 5, 2, 6, 3, 7
#   Upper-right (side 2): 7, 11, 16, 21, 27, 33
#   Lower-right (side 3): 33, 38, 43, 47, 51, 54
#   Bottom      (side 4): 54, 50, 53, 49, 52, 48
#   Lower-left  (side 5): 48, 44, 39, 34, 28, 22
#   Upper-left  (side 6): 22, 17, 12, 8, 4, 1
#
# Adjacent sides share their corner intersection (the last ID of one side equals
# the first ID of the next), giving 30 unique coastal intersections total.
COASTAL_INTERSECTIONS <- c(
   1,  5,  2,  6,  3,  7,   # top side
  11, 16, 21, 27, 33,        # upper-right (7 is the shared corner above)
  38, 43, 47, 51, 54,        # lower-right (33 is the shared corner above)
  50, 53, 49, 52, 48,        # bottom      (54 is the shared corner above)
  44, 39, 34, 28, 22,        # lower-left  (48 is the shared corner above)
  17, 12,  8,  4             # upper-left  (22 is the shared corner above; 1 closes the loop)
)

# The 6 physical board sides, each represented as an ordered vector of 6
# coastal intersection IDs. Consecutive IDs in the vector define the 5 coastal
# edges of that side. Adjacent sides share their corner intersection (the last
# ID of one side equals the first ID of the next), so the full perimeter has
# 6 * 5 = 30 unique coastal edges and 30 unique coastal intersections.
#
# Sides are built by slicing COASTAL_INTERSECTIONS into overlapping windows of
# 6 (stride 5). The final side wraps back to position 1.
BOARD_SIDES <- lapply(0:5, function(k) {
  # Positions 1-based within COASTAL_INTERSECTIONS; stride of 5 per side.
  positions <- (k * 5 + 1):(k * 5 + 6)
  # Wrap positions that exceed 30 back to the start of the perimeter.
  positions[positions > 30] <- positions[positions > 30] - 30
  COASTAL_INTERSECTIONS[positions]
})


# -----------------------------------------------------------------------------
# Core construction functions
# -----------------------------------------------------------------------------

#' Create a single hex object.
#'
#' @param id        Integer hex index (1-19).
#' @param terrain   Character: one of forest/hills/pasture/fields/mountain/desert.
#' @param token     Integer number token (2-12, or NA for desert).
#' @return A named list representing the hex.
make_hex <- function(id, terrain, token) {
  resource <- TERRAIN_RESOURCE[[terrain]]
  pips     <- if (is.na(token)) 0L else PIPS[[as.character(token)]]
  list(
    id       = id,
    terrain  = terrain,
    resource = resource,   # NA for desert
    token    = token,      # NA for desert
    pips     = pips,       # 0 for desert
    has_robber = (terrain == "desert")  # robber starts on desert
  )
}

#' Create a single intersection object.
#'
#' @param id Integer intersection index (1-54).
#' @return A named list representing the intersection.
make_intersection <- function(id) {
  list(
    id           = id,
    owner        = NA_integer_,   # player index who owns a settlement/city here
    structure    = "none",        # "none", "settlement", or "city"
    port         = NULL,          # NULL or a port list (set during board setup)
    is_coastal   = id %in% COASTAL_INTERSECTIONS
  )
}

#' Create a single edge (road slot) object.
#'
#' @param id Integer edge index.
#' @param i  Intersection ID at one end.
#' @param j  Intersection ID at other end.
#' @return A named list representing the edge.
make_edge <- function(id, i, j) {
  list(
    id    = id,
    ends  = c(i, j),   # the two intersection IDs this edge connects
    owner = NA_integer_ # player index who has built a road here, NA if empty
  )
}


# -----------------------------------------------------------------------------
# Board construction
# -----------------------------------------------------------------------------

#' Generate all edges from the intersection adjacency list.
#' Each undirected pair (i, j) with i < j becomes one edge.
#'
#' @return A list of edge objects.
build_edges <- function() {
  edges <- list()
  edge_id <- 1L
  for (i in seq_len(54)) {
    for (j in INTERSECTION_ADJACENCY[[i]]) {
      if (j > i) {  # only add each pair once
        edges[[edge_id]] <- make_edge(edge_id, i, j)
        edge_id <- edge_id + 1L
      }
    }
  }
  edges
}

#' Assign ports to intersections using the 6-side template system.
#'
#' The board perimeter is divided into 6 sides (faces of the outer hexagon).
#' Each side has 5 coastal edge slots, and each of the 6 PORT_SIDE_TEMPLATES
#' defines which slots on that side carry ports and what type they are.
#'
#' The 6 templates are randomly assigned to the 6 physical board sides so that
#' port positions vary each game. Within each assignment, the template's port
#' slots map to consecutive intersection pairs along that side.
#'
#' Each port is attached to both intersections that border its coastal edge,
#' so a player needs a settlement on either of those two intersections to
#' access the port.
#'
#' @param intersections List of intersection objects (will be modified).
#' @param shuffle       Logical; if TRUE randomly assign templates to sides
#'                      (default TRUE — standard Catan uses random port layout).
#' @return The intersections list with port fields populated.
assign_ports <- function(intersections, shuffle = TRUE) {
  # Optionally shuffle which template goes to which physical side.
  templates <- PORT_SIDE_TEMPLATES
  if (shuffle) templates <- sample(templates)

  for (side_idx in seq_len(6)) {
    side_ints <- BOARD_SIDES[[side_idx]]  # 6 intersection IDs for this side
    template  <- templates[[side_idx]]    # 5 port slots for this template

    for (edge_pos in seq_len(5)) {
      port_def <- template[[edge_pos]]
      if (is.null(port_def)) next  # blank slot — no port here

      # Coastal edge at position k connects side_ints[k] and side_ints[k+1].
      int_a <- side_ints[edge_pos]
      int_b <- side_ints[edge_pos + 1L]

      # Attach the same port object to both intersections bordering this edge.
      intersections[[int_a]]$port <- port_def
      intersections[[int_b]]$port <- port_def
    }
  }
  intersections
}

#' Generate a complete Catan board.
#'
#' This is the primary entry point for board creation. It wires together hexes,
#' intersections, and edges and returns a single board list that is passed to
#' all game functions.
#'
#' @param random_terrain Logical; if TRUE shuffle hex terrain (default TRUE).
#' @param random_tokens  Logical; if TRUE shuffle number token placement
#'                       (default TRUE). Ignored for the desert hex.
#' @param random_ports   Logical; if TRUE randomly assign the 6 port-side
#'                       templates to the 6 physical board sides (default TRUE,
#'                       matching standard Catan rules).
#' @param seed           Optional integer random seed for reproducibility.
#' @return A named list with elements:
#'   \describe{
#'     \item{hexes}{List of 19 hex objects.}
#'     \item{intersections}{List of 54 intersection objects.}
#'     \item{edges}{List of edge objects (road slots).}
#'     \item{robber_hex}{Integer index of the hex currently holding the robber.}
#'   }
generate_board <- function(random_terrain = TRUE,
                           random_tokens  = TRUE,
                           random_ports   = TRUE,
                           seed           = NULL) {

  if (!is.null(seed)) set.seed(seed)

  # --- 1. Build terrain sequence -------------------------------------------
  # Expand terrain counts into a full vector of 19 terrain labels.
  terrain_seq <- rep(names(TERRAIN_COUNTS), times = TERRAIN_COUNTS)

  if (random_terrain) {
    terrain_seq <- sample(terrain_seq)
  }
  # Ensure the desert is always placed (it will get no token regardless).

  # --- 2. Assign number tokens ---------------------------------------------
  # The 18 non-desert hexes each receive one token; the desert always gets NA.
  desert_hex_id  <- which(terrain_seq == "desert")
  non_desert_ids <- setdiff(seq_len(19), desert_hex_id)

  if (!random_tokens) {
    # Non-random: walk the spiral in order, skipping the desert hex wherever it
    # falls in the (possibly random) terrain layout, and assign tokens A through
    # R (STANDARD_TOKEN_SEQUENCE) in that order.  This is the official Catan
    # alphabetical-spiral placement method.
    token_assignments <- integer(19)
    token_iter <- 1L
    for (hex_id in HEX_SPIRAL_ORDER) {
      if (hex_id == desert_hex_id) next
      token_assignments[hex_id] <- STANDARD_TOKEN_SEQUENCE[token_iter]
      token_iter <- token_iter + 1L
    }
  } else {
    # Random: shuffle tokens, then reject any arrangement where two red numbers
    # (6 or 8) land on adjacent hexes — as required by the official rules for
    # random setups.  Converges quickly in practice.
    repeat {
      tokens  <- sample(NUMBER_TOKENS)
      red_ids <- non_desert_ids[tokens %in% c(6L, 8L)]
      valid   <- !any(vapply(red_ids, function(h) {
        any(HEX_ADJACENCY[[h]] %in% red_ids)
      }, logical(1)))
      if (valid) break
    }
    token_assignments <- integer(19)
    token_assignments[non_desert_ids] <- tokens
  }

  hex_list <- vector("list", 19)
  for (i in seq_len(19)) {
    tok <- if (terrain_seq[i] == "desert") NA_integer_ else token_assignments[i]
    hex_list[[i]] <- make_hex(i, terrain_seq[i], tok)
  }

  # --- 3. Build intersections and edges ------------------------------------
  intersection_list <- lapply(seq_len(54), make_intersection)
  intersection_list <- assign_ports(intersection_list, shuffle = random_ports)
  edge_list <- build_edges()

  # --- 4. Return board object ----------------------------------------------
  list(
    hexes         = hex_list,
    intersections = intersection_list,
    edges         = edge_list,
    robber_hex    = desert_hex_id   # robber starts on the desert
  )
}


# -----------------------------------------------------------------------------
# Query helpers
# These functions are called frequently by game.R and strategy.R.
# -----------------------------------------------------------------------------

#' Return all hex IDs adjacent to a given intersection.
#'
#' @param board          A board list from generate_board().
#' @param intersection_id Integer intersection ID (1-54).
#' @return Integer vector of hex IDs (length 1-3) adjacent to that intersection.
hexes_at_intersection <- function(board, intersection_id) {
  which(vapply(board$hexes, function(h) {
    intersection_id %in% HEX_INTERSECTIONS[[h$id]]
  }, logical(1)))
}

#' Return all intersection IDs adjacent to a given hex.
#'
#' @param hex_id Integer hex ID (1-19).
#' @return Integer vector of the 6 intersection IDs around the hex.
intersections_of_hex <- function(hex_id) {
  HEX_INTERSECTIONS[[hex_id]]
}

#' Return all intersection IDs adjacent to a given intersection (road distance 1).
#'
#' @param intersection_id Integer intersection ID (1-54).
#' @return Integer vector of directly connected intersection IDs.
adjacent_intersections <- function(intersection_id) {
  INTERSECTION_ADJACENCY[[intersection_id]]
}

#' Return the edge object connecting two intersections, or NULL if none exists.
#'
#' @param board A board list from generate_board().
#' @param i     Intersection ID.
#' @param j     Intersection ID.
#' @return The matching edge list, or NULL.
get_edge <- function(board, i, j) {
  for (e in board$edges) {
    if (setequal(e$ends, c(i, j))) return(e)
  }
  NULL
}

#' Return the edge ID connecting two intersections, or NA if none.
#'
#' @param board A board list from generate_board().
#' @param i     Intersection ID.
#' @param j     Intersection ID.
#' @return Integer edge ID, or NA_integer_.
get_edge_id <- function(board, i, j) {
  for (e in board$edges) {
    if (setequal(e$ends, c(i, j))) return(e$id)
  }
  NA_integer_
}

#' Return the best (lowest rate) port available to a player at their settlements.
#' "Best for resource X" means the port with the lowest give-rate for X.
#'
#' @param board       A board list from generate_board().
#' @param player      A player list (from player.R), used to find owned intersections.
#' @param resource    Character resource name, or NA to find the best general port.
#' @return Named list with elements \code{rate} (integer) and \code{resource}
#'   (character or NA), or NULL if no port is accessible.
best_port_for_player <- function(board, player, resource = NA) {
  best <- list(rate = 4L, resource = NA)  # default: bank 4:1

  for (int_id in player$settlement_locations) {
    port <- board$intersections[[int_id]]$port
    if (is.null(port)) next

    # General port (3:1): applies to any resource.
    if (is.na(port$resource)) {
      if (port$rate < best$rate) best <- port
    }
    # Specific port (2:1): only applies to matching resource.
    if (!is.na(resource) && !is.na(port$resource) && port$resource == resource) {
      if (port$rate < best$rate) best <- port
    }
  }
  best
}

#' Return the trade rate a player has for a given resource.
#'
#' Checks all settled ports, returning the minimum give-rate for that resource.
#' Falls back to 4 (bank rate) if no port is accessible.
#'
#' @param board    A board list from generate_board().
#' @param player   A player list.
#' @param resource Character resource name.
#' @return Integer trade rate (2, 3, or 4).
trade_rate_for <- function(board, player, resource) {
  best_port_for_player(board, player, resource)$rate
}


# -----------------------------------------------------------------------------
# Placement validation
# -----------------------------------------------------------------------------

#' Check whether placing a settlement at an intersection is legal.
#'
#' Rules enforced:
#'   1. The intersection must be unoccupied.
#'   2. No adjacent intersection may already have a settlement or city
#'      (the "distance rule").
#'   3. During non-initial placement the intersection must be reachable by the
#'      player's existing road network (not enforced here — handled in game.R).
#'
#' @param board           A board list from generate_board().
#' @param intersection_id Integer intersection ID.
#' @return Logical TRUE if placement is legal.
is_valid_settlement_spot <- function(board, intersection_id) {
  # Must be unoccupied.
  target <- board$intersections[[intersection_id]]
  if (target$structure != "none") return(FALSE)

  # No adjacent intersection may be occupied (distance rule).
  for (nbr in adjacent_intersections(intersection_id)) {
    if (board$intersections[[nbr]]$structure != "none") return(FALSE)
  }
  TRUE
}

#' Check whether placing a road on a given edge is legal for a player.
#'
#' Rules enforced:
#'   1. The edge must be unoccupied.
#'   2. At least one end of the edge must connect to the player's existing road
#'      or settlement/city (connectivity rule).
#'
#' @param board     A board list from generate_board().
#' @param edge_id   Integer edge ID.
#' @param player_id Integer player index.
#' @return Logical TRUE if placement is legal.
is_valid_road_spot <- function(board, edge_id, player_id) {
  edge <- board$edges[[edge_id]]

  # Edge must be empty.
  if (!is.na(edge$owner)) return(FALSE)

  # At least one endpoint must be connected to this player.
  for (end_int in edge$ends) {
    int_obj <- board$intersections[[end_int]]
    # Connected via own settlement or city.
    if (!is.na(int_obj$owner) && int_obj$owner == player_id) return(TRUE)
    # Connected via an adjacent road owned by this player.
    for (nbr in adjacent_intersections(end_int)) {
      nbr_edge <- get_edge(board, end_int, nbr)
      if (!is.null(nbr_edge) && !is.na(nbr_edge$owner) &&
          nbr_edge$owner == player_id) return(TRUE)
    }
  }
  FALSE
}


# -----------------------------------------------------------------------------
# Board mutation helpers
# These return a *new* board with the change applied (immutable-style updates).
# -----------------------------------------------------------------------------

#' Place a settlement on the board (or upgrade to city).
#'
#' @param board           A board list from generate_board().
#' @param intersection_id Integer intersection ID.
#' @param player_id       Integer player index.
#' @param structure       Character "settlement" or "city".
#' @return Updated board list.
place_structure <- function(board, intersection_id, player_id,
                            structure = "settlement") {
  board$intersections[[intersection_id]]$owner     <- player_id
  board$intersections[[intersection_id]]$structure <- structure
  board
}

#' Place a road on the board.
#'
#' @param board     A board list from generate_board().
#' @param edge_id   Integer edge ID.
#' @param player_id Integer player index.
#' @return Updated board list.
place_road <- function(board, edge_id, player_id) {
  board$edges[[edge_id]]$owner <- player_id
  board
}

#' Move the robber to a new hex.
#'
#' @param board   A board list from generate_board().
#' @param hex_id  Integer target hex ID.
#' @return Updated board list.
move_robber <- function(board, hex_id) {
  # Clear robber from previous hex.
  board$hexes[[board$robber_hex]]$has_robber <- FALSE
  # Place robber on new hex.
  board$hexes[[hex_id]]$has_robber <- TRUE
  board$robber_hex <- hex_id
  board
}


# -----------------------------------------------------------------------------
# Resource production
# -----------------------------------------------------------------------------

#' Determine which (player, resource, amount) triples are produced by a roll.
#'
#' For each hex whose token matches the roll (and which does not have the
#' robber), every adjacent settlement yields 1 of that resource and every
#' adjacent city yields 2.
#'
#' @param board  A board list from generate_board().
#' @param roll   Integer dice total (2-12, not 7).
#' @return A data.frame with columns: player_id (int), resource (chr), amount (int).
#'   May have zero rows if no hex matches or all matching hexes are blocked.
compute_production <- function(board, roll) {
  rows <- list()

  for (hex in board$hexes) {
    # Skip non-matching tokens, desert, and robber-blocked hexes.
    if (is.na(hex$token))      next
    if (hex$token != roll)     next
    if (hex$has_robber)        next

    # Check every intersection bordering this hex.
    for (int_id in intersections_of_hex(hex$id)) {
      int_obj <- board$intersections[[int_id]]
      if (int_obj$structure == "none") next

      amount <- if (int_obj$structure == "city") 2L else 1L
      rows[[length(rows) + 1L]] <- list(
        player_id = int_obj$owner,
        resource  = hex$resource,
        amount    = amount
      )
    }
  }

  if (length(rows) == 0) {
    return(data.frame(player_id = integer(0),
                      resource  = character(0),
                      amount    = integer(0),
                      stringsAsFactors = FALSE))
  }
  do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))
}


# -----------------------------------------------------------------------------
# Longest Road computation
# -----------------------------------------------------------------------------

#' Compute the length of the longest continuous road for a given player.
#'
#' Uses depth-first search over the road graph. A road is "broken" at an
#' intersection occupied by an *opponent's* settlement or city.
#'
#' @param board     A board list from generate_board().
#' @param player_id Integer player index.
#' @return Integer length of the longest road (number of road segments).
longest_road <- function(board, player_id) {

  # Build an adjacency list restricted to this player's roads.
  # road_adj[[i]] = vector of intersection IDs reachable from i via player roads
  road_adj <- vector("list", 54)
  for (i in seq_len(54)) road_adj[[i]] <- integer(0)

  for (edge in board$edges) {
    if (is.na(edge$owner) || edge$owner != player_id) next
    a <- edge$ends[1]
    b <- edge$ends[2]
    road_adj[[a]] <- c(road_adj[[a]], b)
    road_adj[[b]] <- c(road_adj[[b]], a)
  }

  # DFS to find the longest path. We track visited *edges* (not nodes) to
  # allow revisiting intersections via different roads (Catan rule).
  best <- 0L

  dfs <- function(node, visited_edges, depth) {
    updated_best <- depth
    for (nbr in road_adj[[node]]) {
      edge_key <- paste(min(node, nbr), max(node, nbr), sep = "-")
      if (edge_key %in% visited_edges) next

      # A road is broken if an opponent occupies the neighbour intersection.
      nbr_int <- board$intersections[[nbr]]
      if (!is.na(nbr_int$owner) && nbr_int$owner != player_id) next

      updated_best <- max(updated_best,
                          dfs(nbr,
                              c(visited_edges, edge_key),
                              depth + 1L))
    }
    updated_best
  }

  # Try starting DFS from every intersection that has at least one road.
  for (start in seq_len(54)) {
    if (length(road_adj[[start]]) == 0) next
    best <- max(best, dfs(start, character(0), 0L))
  }
  best
}


# -----------------------------------------------------------------------------
# Board summary (useful for debugging and strategy scoring)
# -----------------------------------------------------------------------------

#' Return a summary data.frame of all hexes on the board.
#'
#' @param board A board list from generate_board().
#' @return A data.frame with one row per hex containing id, terrain, resource,
#'   token, pips, and has_robber.
board_hex_summary <- function(board) {
  do.call(rbind, lapply(board$hexes, function(h) {
    data.frame(
      id         = h$id,
      terrain    = h$terrain,
      resource   = ifelse(is.na(h$resource), "none", h$resource),
      token      = ifelse(is.na(h$token), 0L, h$token),
      pips       = h$pips,
      has_robber = h$has_robber,
      stringsAsFactors = FALSE
    )
  }))
}

#' Return a data.frame of all ports on the board.
#'
#' @param board A board list from generate_board().
#' @return A data.frame with columns intersection_id, resource (NA = general),
#'   and rate.
board_port_summary <- function(board) {
  rows <- list()
  for (int in board$intersections) {
    if (!is.null(int$port)) {
      rows[[length(rows) + 1L]] <- data.frame(
        intersection_id = int$id,
        resource        = ifelse(is.na(int$port$resource), "general",
                                 int$port$resource),
        rate            = int$port$rate,
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows) == 0) return(data.frame())
  do.call(rbind, rows)
}
