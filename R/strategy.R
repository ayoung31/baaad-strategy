# =============================================================================
# strategy.R
# Strategy interface definition and concrete strategy implementations.
#
# A "strategy" is a plain R named list containing four functions:
#
#   choose_initial_placement(board, player, taken_ids)  -> intersection id
#   choose_second_placement(board, player, taken_ids)   -> intersection id
#   choose_road_placement(board, player, game_state)    -> edge id
#   choose_action(board, player, game_state)            -> action list
#
# game.R calls these functions by name without knowing which strategy it is
# talking to, so every strategy must implement all four slots.
#
# Three strategies are implemented here:
#   balanced_strategy()    - maximise pip count + resource diversity; cities first
#   sheep_strategy()       - over-invest in wool; route to 2:1 Wool port
#   ore_grain_strategy()   - maximise ore + grain; fast-track city upgrades
#
# Shared helpers (scoring, routing, robber, discard) live at module level and
# are called by all three strategies.
#
# Dependencies (must be sourced before this file):
#   board.R   - is_valid_settlement_spot, is_valid_road_spot,
#               hexes_at_intersection, adjacent_intersections,
#               trade_rate_for, best_port_for_player
#   player.R  - can_build, can_trade, can_play_dev_card, count_resources
# =============================================================================


# =============================================================================
# game_state structure (defined here for reference; constructed in game.R)
#
# game_state <- list(
#   players   = list(...),  # all player objects (read-only inside strategies)
#   turn      = <int>,      # turns elapsed since game start
#   active_id = <int>,      # player ID currently taking their turn
#   deck_size = <int>       # dev cards remaining in the deck
# )
# =============================================================================


# =============================================================================
# action list format (returned by choose_action; dispatched by game.R)
#
# list(type = "build_road",          edge_id = <int>)
# list(type = "build_settlement",    intersection_id = <int>)
# list(type = "build_city",          intersection_id = <int>)
# list(type = "buy_dev_card")
# list(type = "trade",               give = <chr>, give_count = <int>,
#                                    receive = <chr>)
# list(type = "play_knight",         hex_id = <int>, victim_id = <int>)
# list(type = "play_year_of_plenty", res1 = <chr>, res2 = <chr>)
# list(type = "play_monopoly",       resource = <chr>)
# list(type = "play_road_building",  edge1 = <int>, edge2 = <int>)
# list(type = "done")
# =============================================================================


# =============================================================================
# Shared scoring helpers
# =============================================================================

#' Sum the pip counts of all non-desert hexes adjacent to an intersection.
#'
#' This is the raw expected-resource-per-turn value for a spot.
#' Maximum possible: 3 hexes × 5 pips = 15 (three 6/8 hexes — very rare).
#'
#' @param board          Board list from board.R.
#' @param intersection_id Integer intersection ID (1-54).
#' @return Integer total pip count.
score_intersection <- function(board, intersection_id) {
  hex_ids <- hexes_at_intersection(board, intersection_id)
  total   <- 0L
  for (hid in hex_ids) {
    total <- total + board$hexes[[hid]]$pips
  }
  total
}

#' Pip-sum score plus a bonus for each distinct resource type at an intersection.
#'
#' Used by balanced_strategy to reward spots that provide multiple different
#' resources, reducing the risk of being starved on any one type.
#'
#' @param board            Board list.
#' @param intersection_id  Integer intersection ID.
#' @param diversity_weight Numeric bonus per distinct resource type (default 1).
#' @return Numeric score.
score_intersection_diversity <- function(board, intersection_id,
                                        diversity_weight = 1) {
  hex_ids   <- hexes_at_intersection(board, intersection_id)
  pip_sum   <- 0L
  resources <- character(0)

  for (hid in hex_ids) {
    h <- board$hexes[[hid]]
    pip_sum   <- pip_sum + h$pips
    if (!is.na(h$resource)) resources <- c(resources, h$resource)
  }

  n_distinct <- length(unique(resources))
  pip_sum + diversity_weight * n_distinct
}

#' Sum pips from adjacent hexes that produce a specific resource.
#'
#' Used by sheep_strategy (resource = "wool") and ore_grain_strategy
#' (resource = "ore" or "grain") to weight placements toward their
#' target resource.
#'
#' @param board           Board list.
#' @param intersection_id Integer intersection ID.
#' @param resource        Character resource name.
#' @return Integer pip total from matching hexes only.
score_intersection_for_resource <- function(board, intersection_id, resource) {
  hex_ids <- hexes_at_intersection(board, intersection_id)
  total   <- 0L
  for (hid in hex_ids) {
    h <- board$hexes[[hid]]
    if (!is.na(h$resource) && h$resource == resource) {
      total <- total + h$pips
    }
  }
  total
}

#' Create a gap-aware scoring function for settlement placement.
#'
#' Wraps a base scoring function with a bonus for pips of resource types that
#' the player's current network does NOT yet produce. Prevents specialised
#' strategies from being completely starved of infrastructure resources
#' (lumber, brick) by nudging their second — and subsequent — settlement picks
#' toward filling coverage gaps.
#'
#' Balanced already achieves this via diversity_weight; this helper is for
#' strategies whose base score_fn ignores non-target resources.
#'
#' @param board          Board list.
#' @param player         Player list; settlement_locations and city_locations
#'                       determine which resources are already covered.
#' @param base_fn        Base scoring function(board, id) -> numeric.
#' @param balance_weight Numeric bonus per pip of each uncovered resource type.
#' @return A new function(board, id) -> numeric that adds the gap bonus.
make_gap_fn <- function(board, player, base_fn, balance_weight) {
  # Determine which resource types the player's current network produces.
  covered <- character(0)
  for (int_id in c(player$settlement_locations, player$city_locations)) {
    for (hid in hexes_at_intersection(board, int_id)) {
      r <- board$hexes[[hid]]$resource
      if (!is.na(r)) covered <- union(covered, r)
    }
  }

  function(b, id) {
    base      <- base_fn(b, id)
    gap_bonus <- 0
    for (hid in hexes_at_intersection(b, id)) {
      r <- b$hexes[[hid]]$resource
      if (!is.na(r) && !(r %in% covered)) {
        gap_bonus <- gap_bonus + balance_weight * b$hexes[[hid]]$pips
      }
    }
    base + gap_bonus
  }
}

#' Return all intersection IDs that are currently legal settlement spots.
#'
#' Filters all 54 intersections to those that pass is_valid_settlement_spot()
#' AND are not already in taken_ids. Strategies call this before any scoring
#' loop to avoid iterating over illegal candidates.
#'
#' @param board     Board list.
#' @param taken_ids Integer vector of intersection IDs already occupied.
#' @return Integer vector of valid intersection IDs.
valid_settlement_candidates <- function(board, taken_ids) {
  candidates <- integer(0)
  for (id in seq_len(54)) {
    if (id %in% taken_ids) next
    if (is_valid_settlement_spot(board, id)) {
      candidates <- c(candidates, id)
    }
  }
  candidates
}

#' Return all edge IDs where the player can legally place a road.
#'
#' @param board  Board list.
#' @param player Player list.
#' @return Integer vector of valid edge IDs.
valid_road_candidates <- function(board, player) {
  candidates <- integer(0)
  for (e in board$edges) {
    if (is_valid_road_spot(board, e$id, player$id)) {
      candidates <- c(candidates, e$id)
    }
  }
  candidates
}

#' Return all intersection IDs reachable by placing exactly up to `depth` roads.
#'
#' Performs a BFS outward from the player's existing road network endpoints.
#' Used by road-placement logic to plan multi-step routes toward target
#' intersections (e.g. the Wool port for sheep_strategy).
#'
#' "Reachable" means: connected to the player's network by at most `depth`
#' additional road placements along currently unoccupied edges. An intersection
#' blocked by an opponent's settlement/city is not passable.
#'
#' @param board  Board list.
#' @param player Player list.
#' @param depth  Integer; maximum additional roads to consider.
#' @return Integer vector of reachable intersection IDs (may include current
#'         network endpoints if depth >= 0).
reachable_intersections <- function(board, player, depth) {
  if (depth < 0L) return(integer(0))

  # Seed the frontier with all intersections the player currently touches:
  # any intersection adjacent to one of their roads, plus settlement/city spots.
  owned_road_ends <- integer(0)
  for (e in board$edges) {
    if (!is.na(e$owner) && e$owner == player$id) {
      owned_road_ends <- union(owned_road_ends, e$ends)
    }
  }
  # Also include settlement and city locations as starting points.
  starts <- union(owned_road_ends,
                  union(player$settlement_locations, player$city_locations))

  if (length(starts) == 0L) return(integer(0))

  visited <- starts
  frontier <- starts

  for (d in seq_len(depth)) {
    next_frontier <- integer(0)

    for (int_id in frontier) {
      # Check whether this intersection is passable (not blocked by opponent).
      int_obj <- board$intersections[[int_id]]
      if (!is.na(int_obj$owner) && int_obj$owner != player$id) next

      # Expand to all adjacent intersections via unoccupied edges.
      for (nb in adjacent_intersections(int_id)) {
        if (nb %in% visited) next

        # The edge connecting int_id and nb must be unoccupied to build a road.
        e <- get_edge(board, int_id, nb)
        if (!is.null(e) && is.na(e$owner)) {
          visited       <- c(visited, nb)
          next_frontier <- c(next_frontier, nb)
        }
      }
    }

    frontier <- next_frontier
    if (length(frontier) == 0L) break
  }

  visited
}


# =============================================================================
# Shared road-routing helper
# =============================================================================

#' Choose the road edge that moves the player closest to a target intersection.
#'
#' Among all currently valid road placements, selects the edge whose endpoint
#' is closest to `target_id` by BFS distance along unoccupied edges (ignoring
#' the player's road constraint — this is a planning distance, not a placement
#' distance).
#'
#' Falls back to the first valid candidate if no candidate reduces distance.
#'
#' @param board     Board list.
#' @param player    Player list.
#' @param target_id Integer intersection ID to route toward.
#' @return Integer edge ID.
road_toward <- function(board, player, target_id, candidates = NULL) {
  # Allow callers to supply a pre-filtered candidate set (e.g. during initial
  # setup where only edges adjacent to the just-placed settlement are legal).
  if (is.null(candidates)) candidates <- valid_road_candidates(board, player)
  if (length(candidates) == 0L) return(NA_integer_)

  # BFS from target_id to all intersections — used to rank candidates.
  dist_from_target <- bfs_distances(board, target_id)

  best_edge <- candidates[1]
  best_dist <- Inf

  for (eid in candidates) {
    e <- board$edges[[eid]]
    # The "progress" of this edge is the minimum distance of its endpoints to
    # the target (taking the closer end).
    d <- min(dist_from_target[e$ends[1]], dist_from_target[e$ends[2]],
             na.rm = TRUE)
    if (d < best_dist) {
      best_dist <- d
      best_edge <- eid
    }
  }

  best_edge
}

#' BFS distances from a source intersection to all other intersections.
#'
#' Traverses along all board edges regardless of ownership (planning use only).
#' Returns a named integer vector of length 54; unreachable nodes get Inf.
#'
#' @param board     Board list.
#' @param source_id Integer intersection ID to start BFS from.
#' @return Named numeric vector: distance from source_id to each intersection.
bfs_distances <- function(board, source_id) {
  dist <- rep(Inf, 54)
  dist[source_id] <- 0
  queue <- source_id

  while (length(queue) > 0L) {
    current  <- queue[1]
    queue    <- queue[-1]
    for (nb in adjacent_intersections(current)) {
      if (is.infinite(dist[nb])) {
        dist[nb] <- dist[current] + 1
        queue    <- c(queue, nb)
      }
    }
  }

  dist
}


# =============================================================================
# Shared game-logic helpers
# =============================================================================

#' Choose which hex to place the robber on.
#'
#' Shared across all three strategies (per Decision 10 in the implementation
#' plan). The robber targets the leading player (highest visible VP). Among
#' all hexes adjacent to the leader's structures, prefer the highest-pip hex.
#' Falls back to the highest-pip non-desert hex if the leader has no exposed
#' intersections or if the active player IS the leader.
#'
#' Rules enforced:
#'   - Must move the robber (cannot stay on current robber_hex).
#'   - Cannot place on the desert.
#'
#' @param board     Board list.
#' @param player    Player list of the active player.
#' @param players   Full list of all player objects.
#' @return Integer hex ID to place the robber on.
choose_robber_placement <- function(board, player, players) {
  current_robber_hex <- board$robber_hex

  # Build the set of moveable hexes: non-desert and not the current robber hex.
  moveable <- Filter(function(h) {
    h$terrain != "desert" && h$id != current_robber_hex
  }, board$hexes)

  # Find the leader: highest PUBLIC vp among opponents.
  opponents <- Filter(function(p) p$id != player$id, players)
  if (length(opponents) == 0L) {
    # Solo scenario (shouldn't occur in normal play) — pick highest-pip hex.
    return(moveable[[which.max(vapply(moveable, `[[`, numeric(1), "pips"))]]$id)
  }

  leader <- opponents[[which.max(vapply(opponents, `[[`, integer(1), "vp"))]]

  # Collect all hex IDs adjacent to the leader's structures.
  leader_structure_ids <- c(leader$settlement_locations, leader$city_locations)
  leader_hex_ids <- integer(0)
  for (int_id in leader_structure_ids) {
    leader_hex_ids <- union(leader_hex_ids,
                            hexes_at_intersection(board, int_id))
  }

  # Filter moveable hexes to those adjacent to the leader; rank by pip count.
  leader_moveable <- Filter(function(h) h$id %in% leader_hex_ids, moveable)

  if (length(leader_moveable) > 0L) {
    best <- leader_moveable[[which.max(
      vapply(leader_moveable, `[[`, numeric(1), "pips")
    )]]
    return(best$id)
  }

  # Fallback: highest-pip moveable hex regardless of who is adjacent.
  moveable[[which.max(vapply(moveable, `[[`, numeric(1), "pips"))]]$id
}

#' Choose which victim to steal from after placing the robber.
#'
#' Returns the player ID of the opponent with the most resource cards among
#' those with a settlement or city adjacent to the new robber hex. Returns
#' NA_integer_ if no valid victim exists (e.g. no opponents are adjacent).
#'
#' @param board    Board list.
#' @param player   Active player.
#' @param players  All player objects.
#' @param hex_id   Hex where the robber was just placed.
#' @return Integer player ID to steal from, or NA_integer_.
choose_steal_victim <- function(board, player, players, hex_id) {
  adj_ints <- HEX_INTERSECTIONS[[hex_id]]

  victim_ids <- integer(0)
  for (int_id in adj_ints) {
    owner <- board$intersections[[int_id]]$owner
    if (!is.na(owner) && owner != player$id) {
      victim_ids <- union(victim_ids, owner)
    }
  }

  if (length(victim_ids) == 0L) return(NA_integer_)

  # Target the opponent with the most cards (maximum steal value).
  card_counts <- vapply(victim_ids, function(vid) {
    count_resources(players[[vid]])
  }, integer(1))

  victim_ids[which.max(card_counts)]
}

#' Decide which resources to discard when a 7 is rolled.
#'
#' Strategy-aware: each strategy preserves its most-valued resources and
#' discards surpluses. The discard must remove exactly discard_count(player)
#' cards (from player.R).
#'
#' @param player        Player list (pre-discard).
#' @param strategy_name Character; one of "balanced", "sheep", "ore_grain".
#' @return Updated player list with cards discarded.
choose_discard <- function(player, strategy_name) {
  n <- discard_count(player)
  if (n == 0L) return(player)

  # Define resource priority (most important = keep last = lowest discard priority).
  # We discard the LEAST important resources first.
  priority <- switch(strategy_name,
    "balanced" = c("wool", "lumber", "brick", "grain", "ore"),  # keep ore+grain
    "sheep"    = c("lumber", "brick", "ore", "grain", "wool"),  # keep wool
    "ore_grain"= c("wool", "lumber", "brick", "grain", "ore"),  # keep ore+grain
    # Default: same as balanced.
    c("wool", "lumber", "brick", "grain", "ore")
  )
  # priority[1] is discarded first when in surplus

  remaining <- n
  for (res in priority) {
    if (remaining == 0L) break
    amt <- player$resources[[res]]
    if (amt == 0L) next
    discard_amt  <- min(amt, remaining)
    player       <- remove_resource(player, res, discard_amt)
    remaining    <- remaining - discard_amt
  }

  player
}


# =============================================================================
# Trade helper (shared)
# =============================================================================

#' Execute all profitable trades toward a build goal.
#'
#' For the given target build item, checks whether any single trade would bring
#' the player closer to affording it. Iterates until no further trade helps.
#' Uses the player's best available port rate for each resource.
#'
#' @param board   Board list.
#' @param player  Player list.
#' @param item    Character; build target ("road", "settlement", "city",
#'                "dev_card").
#' @return Updated player list after all beneficial trades.
trade_toward <- function(board, player, item) {
  cost <- BUILD_COSTS[[item]]

  repeat {
    # Identify which resources are still needed.
    needed <- names(which(cost > player$resources[names(cost)]))
    if (length(needed) == 0L) break  # already can afford it

    # For each resource the player holds in surplus, try trading it for needed.
    traded <- FALSE
    for (res in names(player$resources)) {
      rate <- trade_rate_for(board, player, res)
      if (!can_trade(player, res, rate)) next

      # Only trade this resource if it is not itself needed for the build.
      shortage <- cost[[res]] - player$resources[[res]]
      if (!is.na(shortage) && shortage > 0L) next

      # Trade for whichever needed resource has the largest gap.
      for (want in needed) {
        player  <- do_trade(player, res, rate, want)
        traded  <- TRUE
        break
      }
      if (traded) break
    }

    if (!traded) break  # no trade made progress; stop
  }

  player
}


# =============================================================================
# Settlement target selection (shared)
# =============================================================================

#' Find the best unoccupied intersection to work toward, scored by a function.
#'
#' Returns the intersection ID with the highest score among all valid
#' settlement candidates not yet reachable in zero steps (i.e. not directly
#' adjacent to the player's current road network endpoint, so this is a
#' planning target rather than an immediate placement).
#'
#' @param board      Board list.
#' @param player     Player list.
#' @param score_fn   Function(board, intersection_id) -> numeric score.
#' @param taken_ids  Integer vector of already-occupied intersections.
#' @return Integer intersection ID of the best target, or NA_integer_.
best_settlement_target <- function(board, player, score_fn, taken_ids) {
  candidates <- valid_settlement_candidates(board, taken_ids)
  if (length(candidates) == 0L) return(NA_integer_)

  scores <- vapply(candidates, function(id) score_fn(board, id), numeric(1))
  candidates[which.max(scores)]
}


# =============================================================================
# Port finder helpers
# =============================================================================

#' Return all intersection IDs that border a port for a specific resource.
#'
#' @param board    Board list.
#' @param resource Character resource, or NA for general (3:1) ports.
#' @return Integer vector of intersection IDs.
port_intersections <- function(board, resource) {
  result <- integer(0)
  for (int in board$intersections) {
    if (is.null(int$port)) next
    port_res <- int$port$resource
    match <- if (is.na(resource)) is.na(port_res) else (!is.na(port_res) && port_res == resource)
    if (match) result <- c(result, int$id)
  }
  result
}

#' Return the intersection ID of the closest Wool port intersection to a player.
#'
#' "Closest" is measured by BFS distance from any of the player's currently
#' placed settlements/cities/road endpoints. Used by sheep_strategy to decide
#' whether to route toward the port.
#'
#' @param board  Board list.
#' @param player Player list.
#' @return Integer intersection ID of the nearest Wool port spot, or NA_integer_.
nearest_wool_port_intersection <- function(board, player) {
  wool_port_ints <- port_intersections(board, "wool")
  if (length(wool_port_ints) == 0L) return(NA_integer_)

  # All intersections currently in the player's network.
  network <- union(player$settlement_locations,
                   union(player$city_locations, player$road_locations))
  # road_locations are edge IDs; get their endpoints instead.
  road_ends <- integer(0)
  for (eid in player$road_locations) {
    road_ends <- union(road_ends, board$edges[[eid]]$ends)
  }
  network <- union(player$settlement_locations,
                   union(player$city_locations, road_ends))

  if (length(network) == 0L) {
    # No roads/settlements yet — measure from all board intersections at dist 0
    # just return the first wool port intersection as default.
    return(wool_port_ints[1])
  }

  # For each wool port intersection, find the min BFS distance from any network
  # node.
  best_int  <- NA_integer_
  best_dist <- Inf

  for (wid in wool_port_ints) {
    dists <- bfs_distances(board, wid)
    min_d <- min(dists[network])
    if (min_d < best_dist) {
      best_dist <- min_d
      best_int  <- wid
    }
  }

  best_int
}

#' Return the intersection ID of the closest Ore or Grain port intersection.
#'
#' Considers all 2:1 Ore and 2:1 Grain port intersections together and returns
#' the one with the shortest BFS distance from the player's current network.
#' Used by ore_grain_strategy to decide whether to route toward a port.
#'
#' @param board  Board list.
#' @param player Player list.
#' @return Integer intersection ID of the nearest Ore/Grain port spot, or NA_integer_.
nearest_og_port_intersection <- function(board, player) {
  og_port_ints <- c(port_intersections(board, "ore"), port_intersections(board, "grain"))
  if (length(og_port_ints) == 0L) return(NA_integer_)

  road_ends <- integer(0)
  for (eid in player$road_locations) {
    road_ends <- union(road_ends, board$edges[[eid]]$ends)
  }
  network <- union(player$settlement_locations,
                   union(player$city_locations, road_ends))

  if (length(network) == 0L) return(og_port_ints[1])

  best_int  <- NA_integer_
  best_dist <- Inf

  for (pid in og_port_ints) {
    dists <- bfs_distances(board, pid)
    min_d <- min(dists[network])
    if (min_d < best_dist) {
      best_dist <- min_d
      best_int  <- pid
    }
  }

  best_int
}


# =============================================================================
# balanced_strategy
# =============================================================================

#' Construct the balanced strategy.
#'
#' Philosophy: maximise expected resource production AND resource diversity.
#' Prioritise city upgrades (best VP/resource ratio) and use bank/port trading
#' to smooth resource shortfalls. Does not fixate on any single resource type.
#'
#' @param diversity_weight Numeric bonus per distinct resource at a spot (default 1).
#' @return Named list of four strategy functions.
balanced_strategy <- function(diversity_weight = 1, closing_vp = 5) {

  # --- Internal scoring function for this strategy ---
  score_fn <- function(board, id) {
    score_intersection_diversity(board, id, diversity_weight)
  }

  list(

    # -------------------------------------------------------------------------
    # choose_initial_placement
    # First settlement in the snake draft. Score all valid candidates by
    # pip sum + diversity and pick the highest.
    # -------------------------------------------------------------------------
    choose_initial_placement = function(board, player, taken_ids) {
      candidates <- valid_settlement_candidates(board, taken_ids)
      if (length(candidates) == 0L) stop("No valid settlement candidates")

      scores <- vapply(candidates, function(id) score_fn(board, id), numeric(1))
      candidates[which.max(scores)]
    },

    # -------------------------------------------------------------------------
    # choose_second_placement
    # Second settlement (reverse snake pass). Re-score on the updated board.
    # Same logic as the first pick — the diversity score naturally avoids
    # over-stacking on one resource since the first placement already covers
    # some types.
    # -------------------------------------------------------------------------
    choose_second_placement = function(board, player, taken_ids) {
      candidates <- valid_settlement_candidates(board, taken_ids)
      if (length(candidates) == 0L) stop("No valid settlement candidates")

      scores <- vapply(candidates, function(id) score_fn(board, id), numeric(1))
      candidates[which.max(scores)]
    },

    # -------------------------------------------------------------------------
    # choose_road_placement
    # During setup: route toward the highest-scoring unoccupied intersection
    # reachable within 3 roads.
    # During normal play: extend toward the best remaining settlement target,
    # or toward Longest Road if already at 5 settlements.
    #
    # must_connect_to: when non-NULL (initial setup), only edges adjacent to
    # that intersection ID are considered, enforcing the Catan rule that the
    # setup road must connect directly to the settlement just placed.
    # -------------------------------------------------------------------------
    choose_road_placement = function(board, player, game_state,
                                     must_connect_to = NULL) {
      candidates <- valid_road_candidates(board, player)

      # Setup constraint: restrict to edges adjacent to the new settlement.
      if (!is.null(must_connect_to)) {
        candidates <- Filter(function(eid) {
          must_connect_to %in% board$edges[[eid]]$ends
        }, candidates)
      }

      if (length(candidates) == 0L) stop("No valid road candidates")

      taken_ids <- unlist(lapply(game_state$players, function(p) {
        c(p$settlement_locations, p$city_locations)
      }))

      # If at settlement limit, just extend the road network freely.
      if (length(player$settlement_locations) >= PIECE_LIMITS[["settlement"]]) {
        return(candidates[1])
      }

      # Find the best settlement target not yet reachable.
      target <- best_settlement_target(board, player, score_fn, taken_ids)
      if (is.na(target)) return(candidates[1])

      road_toward(board, player, target, candidates = candidates)
    },

    # -------------------------------------------------------------------------
    # choose_action
    # Priority: play useful dev card → trade → city → settlement → dev card
    # → road → done.
    # Called repeatedly until returning list(type = "done").
    # -------------------------------------------------------------------------
    choose_action = function(board, player, game_state) {

      # --- Late-game closing mode ---
      if (compute_vp(player) >= closing_vp) {
        return(closing_action(board, player, game_state, score_fn))
      }

      # --- 1. Play a dev card if beneficial ---
      action <- balanced_play_dev_card(board, player, game_state)
      if (!is.null(action)) return(action)

      # --- 2. Trade toward the best build goal ---
      # Try trading toward city first; if not reachable after trades, try
      # settlement, then dev card, then road as a last resort.
      settlement_count_trade <- length(player$settlement_locations) +
                                length(player$city_locations)
      for (goal in c("city", "settlement", "dev_card", "road")) {
        if (goal == "city"       && length(player$settlement_locations) == 0L) next
        if (goal == "dev_card"   && game_state$deck_size == 0L) next
        if (goal == "road"       && settlement_count_trade >= PIECE_LIMITS[["settlement"]]) next

        player_after_trade <- trade_toward(board, player, goal)
        if (can_build(player_after_trade, goal)) {
          # Commit the trades (return them as individual trade actions is
          # complex; instead we reflect them in player and fall through to build).
          # Since choose_action is called in a loop, we return the first trade
          # action if any trades are needed.
          if (!identical(player_after_trade$resources, player$resources)) {
            # Find the first trade that was made and return it.
            return(first_trade_action(board, player, goal))
          }
          break
        }
      }

      # --- 3. Build: city ---
      if (length(player$settlement_locations) > 0L && can_build(player, "city")) {
        # Upgrade the settlement with the highest pip score.
        best_city <- player$settlement_locations[
          which.max(vapply(player$settlement_locations,
                           function(id) score_fn(board, id), numeric(1)))
        ]
        return(list(type = "build_city", intersection_id = best_city))
      }

      # --- 4. Build: settlement ---
      taken_ids <- unlist(lapply(game_state$players, function(p) {
        c(p$settlement_locations, p$city_locations)
      }))
      if (can_build(player, "settlement")) {
        # Place on the best reachable valid spot.
        reachable <- reachable_intersections(board, player, depth = 0L)
        reachable_valid <- Filter(function(id) {
          is_valid_settlement_spot(board, id) && !(id %in% taken_ids)
        }, reachable)

        if (length(reachable_valid) > 0L) {
          scores  <- vapply(reachable_valid, function(id) score_fn(board, id),
                            numeric(1))
          best_id <- reachable_valid[which.max(scores)]
          return(list(type = "build_settlement", intersection_id = best_id))
        }
      }

      # --- 5. Buy dev card ---
      if (can_build(player, "dev_card") && game_state$deck_size > 0L) {
        return(list(type = "buy_dev_card"))
      }

      # --- 6. Build road (only if it opens up a new settlement spot) ---
      if (can_build(player, "road")) {
        target <- best_settlement_target(board, player, score_fn, taken_ids)
        if (!is.na(target)) {
          # Only build a road if we are not already adjacent to the target.
          reachable_now <- reachable_intersections(board, player, depth = 0L)
          if (!(target %in% reachable_now)) {
            eid <- road_toward(board, player, target)
            if (!is.na(eid)) return(list(type = "build_road", edge_id = eid))
          }
        }
      }

      list(type = "done")
    }
  )
}

# Helper: find the first trade action that moves toward `item`.
# Returns an action list(type = "trade", ...) or NULL.
first_trade_action <- function(board, player, item) {
  cost   <- BUILD_COSTS[[item]]
  needed <- names(which(cost > player$resources[names(cost)]))
  if (length(needed) == 0L) return(NULL)

  for (res in names(player$resources)) {
    rate <- trade_rate_for(board, player, res)
    if (!can_trade(player, res, rate)) next
    shortage <- cost[[res]] - player$resources[[res]]
    if (!is.na(shortage) && shortage > 0L) next
    for (want in needed) {
      return(list(type = "trade", give = res,
                  give_count = rate, receive = want))
    }
  }
  NULL
}

# Helper: decide whether balanced_strategy should play a dev card this action.
# Returns an action list or NULL.
balanced_play_dev_card <- function(board, player, game_state) {
  # Play Knight only when close to the Largest Army threshold.
  if (can_play_dev_card(player, "knight")) {
    close_to_army <- (player$knights_played >= 2L)
    if (close_to_army) {
      hex_id    <- choose_robber_placement(board, player, game_state$players)
      victim_id <- choose_steal_victim(board, player, game_state$players, hex_id)
      return(list(type = "play_knight", hex_id = hex_id, victim_id = victim_id))
    }
  }

  # Play Year of Plenty toward the next city if possible.
  if (can_play_dev_card(player, "year_of_plenty")) {
    cost    <- BUILD_COSTS[["city"]]
    needed  <- names(which(cost > player$resources[names(cost)]))
    if (length(needed) >= 1L) {
      r1 <- needed[1]
      r2 <- if (length(needed) >= 2L) needed[2] else needed[1]
      return(list(type = "play_year_of_plenty", res1 = r1, res2 = r2))
    }
  }

  # Play Monopoly for whatever resource the player is most short of overall.
  if (can_play_dev_card(player, "monopoly")) {
    # Choose the resource with the largest gap vs. city cost.
    cost     <- BUILD_COSTS[["city"]]
    gaps     <- pmax(cost - player$resources[names(cost)], 0L)
    if (sum(gaps) > 0L) {
      target_res <- names(which.max(gaps))
      return(list(type = "play_monopoly", resource = target_res))
    }
  }

  NULL
}


# =============================================================================
# sheep_strategy
# =============================================================================

#' Construct the sheep (wool) strategy.
#'
#' Philosophy: over-invest in wool production, route to the 2:1 Wool port,
#' and spend wool surplus on dev cards (pursuing Largest Army as a VP path).
#' This strategy is intentionally suboptimal — it demonstrates that fixating
#' on wool is a losing approach because wool cannot buy cities and the Wool
#' port is the least impactful 2:1 port.
#'
#' @param wool_weight   Numeric multiplier on wool pips in placement scoring
#'                      (default 2, as described in the implementation plan).
#' @param total_weight  Numeric multiplier on total pips as a tie-breaker
#'                      (default 0.5).
#' @return Named list of four strategy functions.
sheep_strategy <- function(wool_weight = 2, total_weight = 0.5, closing_vp = 5,
                           balance_weight = 1) {

  # Composite scoring function: heavily weights wool pips, small bonus for
  # total production so the strategy doesn't pick zero-pip wool spots.
  score_fn <- function(board, id) {
    wool_pips  <- score_intersection_for_resource(board, id, "wool")
    total_pips <- score_intersection(board, id)
    wool_pips * wool_weight + total_pips * total_weight
  }

  list(

    # -------------------------------------------------------------------------
    # choose_initial_placement
    # Score by wool-heavy formula. Pick the highest wool-producing valid spot.
    # -------------------------------------------------------------------------
    choose_initial_placement = function(board, player, taken_ids) {
      candidates <- valid_settlement_candidates(board, taken_ids)
      if (length(candidates) == 0L) stop("No valid settlement candidates")

      scores <- vapply(candidates, function(id) score_fn(board, id), numeric(1))
      candidates[which.max(scores)]
    },

    # -------------------------------------------------------------------------
    # choose_second_placement
    # Hard-target the 2:1 Wool port (Decision 8: commit even at production cost).
    # If any Wool port intersection is still available, score them separately:
    # port intersections get a large bonus added to their wool score.
    # Otherwise fall back to the same wool-heavy scoring as the first pick.
    # -------------------------------------------------------------------------
    choose_second_placement = function(board, player, taken_ids) {
      candidates <- valid_settlement_candidates(board, taken_ids)
      if (length(candidates) == 0L) stop("No valid settlement candidates")

      # Determine what the first settlement already covers.
      covered_first <- character(0)
      for (int_id in c(player$settlement_locations, player$city_locations)) {
        for (hid in hexes_at_intersection(board, int_id)) {
          r <- board$hexes[[hid]]$resource
          if (!is.na(r)) covered_first <- union(covered_first, r)
        }
      }
      has_lb <- all(c("lumber", "brick") %in% covered_first)

      gap_fn <- make_gap_fn(board, player, score_fn, balance_weight)

      wool_port_ints <- port_intersections(board, "wool")

      if (!has_lb) {
        # Infrastructure first: restrict candidates to those that provide at
        # least one of the missing infra resources (lumber, brick).
        # Prefer intersections covering BOTH; fall back to at least one.
        # Port bonus still applies within the filtered set so an intersection
        # that provides infra AND borders a Wool port scores higher.
        missing_infra <- setdiff(c("lumber", "brick"), covered_first)
        provides_res  <- function(id, res) {
          any(vapply(hexes_at_intersection(board, id), function(hid) {
            isTRUE(board$hexes[[hid]]$resource == res)
          }, logical(1)))
        }
        both_cands  <- Filter(function(id) all(vapply(missing_infra, function(r) provides_res(id, r), logical(1))), candidates)
        infra_cands <- Filter(function(id) any(vapply(missing_infra, function(r) provides_res(id, r), logical(1))), candidates)
        use_cands   <- if (length(both_cands)  > 0L) both_cands
                       else if (length(infra_cands) > 0L) infra_cands
                       else candidates
      } else {
        use_cands <- candidates
      }

      scores <- vapply(use_cands, function(id) {
        gap_fn(board, id) + if (id %in% wool_port_ints) 100 else 0
      }, numeric(1))
      use_cands[which.max(scores)]
    },

    # -------------------------------------------------------------------------
    # choose_road_placement
    # If not yet on the Wool port: route toward the nearest Wool port
    # intersection using road_toward().
    # Once the port is secured: route toward the next wool-heavy settlement.
    #
    # must_connect_to: setup constraint — see balanced_strategy for details.
    # -------------------------------------------------------------------------
    choose_road_placement = function(board, player, game_state,
                                     must_connect_to = NULL) {
      candidates <- valid_road_candidates(board, player)

      # Setup constraint: restrict to edges adjacent to the new settlement.
      if (!is.null(must_connect_to)) {
        candidates <- Filter(function(eid) {
          must_connect_to %in% board$edges[[eid]]$ends
        }, candidates)
      }

      if (length(candidates) == 0L) stop("No valid road candidates")

      # Check whether the player already controls a Wool port intersection.
      wool_port_ints <- port_intersections(board, "wool")
      has_wool_port  <- any(player$settlement_locations %in% wool_port_ints) ||
                        any(player$city_locations       %in% wool_port_ints)

      if (!has_wool_port) {
        # Route toward the nearest Wool port intersection.
        target <- nearest_wool_port_intersection(board, player)
        if (!is.na(target)) {
          return(road_toward(board, player, target, candidates = candidates))
        }
      }

      # Port secured (or unreachable): route toward best remaining wool spot.
      taken_ids <- unlist(lapply(game_state$players, function(p) {
        c(p$settlement_locations, p$city_locations)
      }))
      target <- best_settlement_target(board, player, score_fn, taken_ids)
      if (!is.na(target)) return(road_toward(board, player, target, candidates = candidates))

      candidates[1]
    },

    # -------------------------------------------------------------------------
    # choose_action
    # Priority: play Knight (Largest Army pursuit) → trade wool via port →
    # buy dev card → settlement → city → road → done.
    # -------------------------------------------------------------------------
    choose_action = function(board, player, game_state) {

      # --- Late-game closing mode ---
      if (compute_vp(player) >= closing_vp) {
        return(closing_action(board, player, game_state, score_fn))
      }

      # --- 1. Play Knight (Largest Army path, but gated — not recklessly early) ---
      # Only play when close to the Largest Army threshold; saving knights
      # until then makes each one more strategically valuable.
      if (can_play_dev_card(player, "knight")) {
        close_to_army <- (player$knights_played >= 2L)
        if (close_to_army) {
          hex_id    <- choose_robber_placement(board, player, game_state$players)
          victim_id <- choose_steal_victim(board, player, game_state$players, hex_id)
          return(list(type = "play_knight", hex_id = hex_id, victim_id = victim_id))
        }
      }

      # --- 2. Play Year of Plenty for ore+grain (enables dev card purchase) ---
      if (can_play_dev_card(player, "year_of_plenty")) {
        return(list(type = "play_year_of_plenty", res1 = "ore", res2 = "grain"))
      }

      # --- 3. Play Monopoly for ore (scarcest resource for this strategy) ---
      if (can_play_dev_card(player, "monopoly")) {
        return(list(type = "play_monopoly", resource = "ore"))
      }

      # --- 4. Trade toward dev card; city is a fallback if dev card blocked ---
      # Simulate-then-commit: only execute the trade if the full sequence
      # actually reaches affordability (prevents wasteful partial trades).
      taken_ids <- unlist(lapply(game_state$players, function(p) {
        c(p$settlement_locations, p$city_locations)
      }))
      settlement_count_trade <- length(player$settlement_locations) +
                                length(player$city_locations)
      for (goal in c("city", "settlement", "dev_card", "road")) {
        if (goal == "city"       && length(player$settlement_locations) == 0L) next
        if (goal == "dev_card"   && game_state$deck_size == 0L)            next
        if (goal == "road"       && settlement_count_trade >= PIECE_LIMITS[["settlement"]]) next
        player_after_trade <- trade_toward(board, player, goal)
        if (can_build(player_after_trade, goal)) {
          if (!identical(player_after_trade$resources, player$resources)) {
            return(first_trade_action(board, player, goal))
          }
          break
        }
      }

      # --- 5. Buy dev card ---
      if (can_build(player, "dev_card") && game_state$deck_size > 0L) {
        return(list(type = "buy_dev_card"))
      }

      # --- 6. Build settlement (expand wool production network) ---
      if (can_build(player, "settlement")) {
        reachable       <- reachable_intersections(board, player, depth = 0L)
        reachable_valid <- Filter(function(id) {
          is_valid_settlement_spot(board, id) && !(id %in% taken_ids)
        }, reachable)

        if (length(reachable_valid) > 0L) {
          # Gap-aware: bonus for resource types not yet in the network.
          gap_fn  <- make_gap_fn(board, player, score_fn, balance_weight)
          scores  <- vapply(reachable_valid, function(id) gap_fn(board, id),
                            numeric(1))
          best_id <- reachable_valid[which.max(scores)]
          return(list(type = "build_settlement", intersection_id = best_id))
        }
      }

      # --- 7. Build city (lower priority; resource starvation emerges naturally) ---
      if (length(player$settlement_locations) > 0L && can_build(player, "city")) {
        best_city <- player$settlement_locations[
          which.max(vapply(player$settlement_locations,
                           function(id) score_fn(board, id), numeric(1)))
        ]
        return(list(type = "build_city", intersection_id = best_city))
      }

      # --- 8. Build road toward Wool port or next wool settlement ---
      # Guard: only hold lumber+brick for settlement saving when a valid
      # settlement spot is already reachable from the current network.
      # If no spot is reachable yet, roads are needed to get there — build freely.
      reachable_now <- reachable_intersections(board, player, depth = 0L)
      reachable_valid_now <- Filter(function(id) {
        is_valid_settlement_spot(board, id) && !(id %in% taken_ids)
      }, reachable_now)
      player_next_wool <- player
      player_next_wool$resources[["wool"]] <- player_next_wool$resources[["wool"]] + 1L
      close_to_settlement <- length(reachable_valid_now) > 0L &&
        can_build(trade_toward(board, player_next_wool, "settlement"), "settlement")
      if (can_build(player, "road") && !close_to_settlement) {
        wool_port_ints <- port_intersections(board, "wool")
        has_wool_port  <- any(player$settlement_locations %in% wool_port_ints) ||
                          any(player$city_locations       %in% wool_port_ints)

        if (!has_wool_port) {
          target <- nearest_wool_port_intersection(board, player)
          if (!is.na(target)) {
            eid <- road_toward(board, player, target)
            if (!is.na(eid)) return(list(type = "build_road", edge_id = eid))
          }
        } else {
          target <- best_settlement_target(board, player, score_fn, taken_ids)
          if (!is.na(target)) {
            eid <- road_toward(board, player, target)
            if (!is.na(eid)) return(list(type = "build_road", edge_id = eid))
          }
        }
      }

      list(type = "done")
    }
  )
}


# =============================================================================
# ore_grain_strategy
# =============================================================================

#' Construct the ore+grain (city engine) strategy.
#'
#' Philosophy: maximise ore and grain production, upgrade settlements to cities
#' as fast as possible. Cities double production on the already-high-value
#' ore/grain hexes, creating a compounding VP lead. Acts as the reference
#' "strong" strategy for comparing against sheep_strategy.
#'
#' @param og_weight    Numeric multiplier on ore+grain pips (default 2).
#' @param total_weight Numeric tie-breaker on total pips (default 0.5).
#' @return Named list of four strategy functions.
ore_grain_strategy <- function(og_weight = 2, total_weight = 0.5, closing_vp = 5,
                               balance_weight = 1) {

  # Combined ore+grain scoring.
  score_fn <- function(board, id) {
    ore_pips   <- score_intersection_for_resource(board, id, "ore")
    grain_pips <- score_intersection_for_resource(board, id, "grain")
    total_pips <- score_intersection(board, id)
    (ore_pips + grain_pips) * og_weight + total_pips * total_weight
  }

  list(

    # -------------------------------------------------------------------------
    # choose_initial_placement
    # Pick the highest ore+grain scoring valid intersection.
    # -------------------------------------------------------------------------
    choose_initial_placement = function(board, player, taken_ids) {
      candidates <- valid_settlement_candidates(board, taken_ids)
      if (length(candidates) == 0L) stop("No valid settlement candidates")

      scores <- vapply(candidates, function(id) score_fn(board, id), numeric(1))
      candidates[which.max(scores)]
    },

    # -------------------------------------------------------------------------
    # choose_second_placement
    # Same ore+grain scoring. If a 2:1 Ore or Grain port is still reachable,
    # add a bonus to its intersections to prioritise port access.
    # -------------------------------------------------------------------------
    choose_second_placement = function(board, player, taken_ids) {
      candidates <- valid_settlement_candidates(board, taken_ids)
      if (length(candidates) == 0L) stop("No valid settlement candidates")

      # Determine what the first settlement already covers.
      covered_first <- character(0)
      for (int_id in c(player$settlement_locations, player$city_locations)) {
        for (hid in hexes_at_intersection(board, int_id)) {
          r <- board$hexes[[hid]]$resource
          if (!is.na(r)) covered_first <- union(covered_first, r)
        }
      }
      has_lb <- all(c("lumber", "brick") %in% covered_first)

      gap_fn <- make_gap_fn(board, player, score_fn,
                            if (has_lb) balance_weight else og_weight)

      ore_port_ints   <- port_intersections(board, "ore")
      grain_port_ints <- port_intersections(board, "grain")

      if (!has_lb) {
        # Infrastructure first: restrict candidates to those that provide at
        # least one of the missing infra resources (lumber, brick).
        # Prefer intersections covering BOTH; fall back to at least one.
        # Port bonus still applies within the filtered set so an intersection
        # that provides infra AND borders an Ore/Grain port scores higher.
        missing_infra <- setdiff(c("lumber", "brick"), covered_first)
        provides_res  <- function(id, res) {
          any(vapply(hexes_at_intersection(board, id), function(hid) {
            isTRUE(board$hexes[[hid]]$resource == res)
          }, logical(1)))
        }
        both_cands  <- Filter(function(id) all(vapply(missing_infra, function(r) provides_res(id, r), logical(1))), candidates)
        infra_cands <- Filter(function(id) any(vapply(missing_infra, function(r) provides_res(id, r), logical(1))), candidates)
        use_cands   <- if (length(both_cands)  > 0L) both_cands
                       else if (length(infra_cands) > 0L) infra_cands
                       else candidates
      } else {
        use_cands <- candidates
      }

      scores <- vapply(use_cands, function(id) {
        gap_fn(board, id) + if (id %in% ore_port_ints || id %in% grain_port_ints) 50 else 0
      }, numeric(1))
      use_cands[which.max(scores)]
    },

    # -------------------------------------------------------------------------
    # choose_road_placement
    # If not yet on an Ore or Grain port: route toward the nearest such port.
    # Once the port is secured: route toward the best ore+grain settlement spot.
    #
    # must_connect_to: setup constraint — see balanced_strategy for details.
    # -------------------------------------------------------------------------
    choose_road_placement = function(board, player, game_state,
                                     must_connect_to = NULL) {
      candidates <- valid_road_candidates(board, player)

      # Setup constraint: restrict to edges adjacent to the new settlement.
      if (!is.null(must_connect_to)) {
        candidates <- Filter(function(eid) {
          must_connect_to %in% board$edges[[eid]]$ends
        }, candidates)
      }

      if (length(candidates) == 0L) stop("No valid road candidates")

      # Check whether the player already controls an Ore or Grain port.
      og_port_ints <- c(port_intersections(board, "ore"), port_intersections(board, "grain"))
      has_og_port  <- any(player$settlement_locations %in% og_port_ints) ||
                      any(player$city_locations       %in% og_port_ints)

      if (!has_og_port) {
        # Route toward the nearest Ore/Grain port intersection.
        target <- nearest_og_port_intersection(board, player)
        if (!is.na(target)) {
          return(road_toward(board, player, target, candidates = candidates))
        }
      }

      # Port secured (or unreachable): route toward best ore+grain settlement spot.
      taken_ids <- unlist(lapply(game_state$players, function(p) {
        c(p$settlement_locations, p$city_locations)
      }))

      target <- best_settlement_target(board, player, score_fn, taken_ids)
      if (!is.na(target)) return(road_toward(board, player, target, candidates = candidates))

      candidates[1]
    },

    # -------------------------------------------------------------------------
    # choose_action
    # Priority: play useful dev card → trade → city (top priority) →
    # dev card → settlement (capped at 3) → road → done.
    # -------------------------------------------------------------------------
    choose_action = function(board, player, game_state) {

      # --- Late-game closing mode ---
      if (compute_vp(player) >= closing_vp) {
        return(closing_action(board, player, game_state, score_fn))
      }

      # --- 1. Play dev card ---
      action <- og_play_dev_card(board, player, game_state)
      if (!is.null(action)) return(action)

      # --- 2. Trade toward the best build goal ---
      # Simulate the full trade sequence first (trade_toward); only commit if
      # it will actually reach affordability. This prevents partial trades
      # that deplete ore/grain without ever reaching city cost.
      settlement_count_trade <- length(player$settlement_locations) +
                                length(player$city_locations)
      for (goal in c("city", "settlement", "dev_card", "road")) {
        if (goal == "city"       && length(player$settlement_locations) == 0L) next
        if (goal == "settlement" && settlement_count_trade >= 4L) next
        if (goal == "dev_card"   && game_state$deck_size == 0L) next
        if (goal == "road"       && settlement_count_trade >= 4L) next
        player_after_trade <- trade_toward(board, player, goal)
        if (can_build(player_after_trade, goal)) {
          if (!identical(player_after_trade$resources, player$resources)) {
            return(first_trade_action(board, player, goal))
          }
          break
        }
      }

      # --- 3. Build city (top priority — this is the whole point) ---
      if (length(player$settlement_locations) > 0L && can_build(player, "city")) {
        best_city <- player$settlement_locations[
          which.max(vapply(player$settlement_locations,
                           function(id) score_fn(board, id), numeric(1)))
        ]
        return(list(type = "build_city", intersection_id = best_city))
      }

      # --- 4. Build settlement (production base before dev cards) ---
      # Expanding the resource network funds more cities; building a settlement
      # is better than a dev card gamble when both are currently affordable.
      taken_ids <- unlist(lapply(game_state$players, function(p) {
        c(p$settlement_locations, p$city_locations)
      }))
      settlement_count <- length(player$settlement_locations) +
                          length(player$city_locations)

      if (settlement_count < 4L && can_build(player, "settlement")) {
        reachable       <- reachable_intersections(board, player, depth = 0L)
        reachable_valid <- Filter(function(id) {
          is_valid_settlement_spot(board, id) && !(id %in% taken_ids)
        }, reachable)

        if (length(reachable_valid) > 0L) {
          # Gap-aware: bonus for resource types not yet in the network.
          gap_fn  <- make_gap_fn(board, player, score_fn, balance_weight)
          scores  <- vapply(reachable_valid, function(id) gap_fn(board, id),
                            numeric(1))
          best_id <- reachable_valid[which.max(scores)]
          return(list(type = "build_settlement", intersection_id = best_id))
        }
      }

      # --- 5. Buy dev card (ore+grain surplus → VP via dev cards) ---
      # Reached only when city is currently out of reach and no settlement
      # can be placed, so these resources are genuinely surplus.
      if (can_build(player, "dev_card") && game_state$deck_size > 0L) {
        return(list(type = "buy_dev_card"))
      }

      # --- 6. Build road toward next settlement spot ---
      if (settlement_count < 4L && can_build(player, "road")) {
        target <- best_settlement_target(board, player, score_fn, taken_ids)
        if (!is.na(target)) {
          reachable_now <- reachable_intersections(board, player, depth = 0L)
          if (!(target %in% reachable_now)) {
            eid <- road_toward(board, player, target)
            if (!is.na(eid)) return(list(type = "build_road", edge_id = eid))
          }
        }
      }

      list(type = "done")
    }
  )
}

# =============================================================================
# Shared late-game closing routine
# =============================================================================

#' Opportunistic closing logic used by all strategies once VP >= closing_vp.
#'
#' When a strategy is in the home stretch, rigid specialisation hurts: the goal
#' is simply to reach 10 VP as fast as possible. This routine uses the same
#' flexible priority chain as balanced_strategy but scores candidates with the
#' calling strategy's own score_fn so placement preferences stay coherent.
#'
#' @param board      Board list.
#' @param player     Player list.
#' @param game_state Game state list.
#' @param score_fn   The calling strategy's intersection scoring function.
#' @return Action list.
closing_action <- function(board, player, game_state, score_fn) {
  taken_ids <- unlist(lapply(game_state$players, function(p) {
    c(p$settlement_locations, p$city_locations)
  }))

  # 1. Play a dev card if it is clearly beneficial.
  action <- balanced_play_dev_card(board, player, game_state)
  if (!is.null(action)) return(action)

  # 2. Trade toward whichever goal is closest.
  for (goal in c("city", "settlement", "dev_card")) {
    if (goal == "city"     && length(player$settlement_locations) == 0L) next
    if (goal == "dev_card" && game_state$deck_size == 0L)                next
    player_after_trade <- trade_toward(board, player, goal)
    if (can_build(player_after_trade, goal)) {
      if (!identical(player_after_trade$resources, player$resources)) {
        return(first_trade_action(board, player, goal))
      }
      break
    }
  }

  # 3. Build city.
  if (length(player$settlement_locations) > 0L && can_build(player, "city")) {
    best_city <- player$settlement_locations[
      which.max(vapply(player$settlement_locations,
                       function(id) score_fn(board, id), numeric(1)))
    ]
    return(list(type = "build_city", intersection_id = best_city))
  }

  # 4. Build settlement on best reachable spot.
  if (can_build(player, "settlement")) {
    reachable       <- reachable_intersections(board, player, depth = 0L)
    reachable_valid <- Filter(function(id) {
      is_valid_settlement_spot(board, id) && !(id %in% taken_ids)
    }, reachable)
    if (length(reachable_valid) > 0L) {
      scores <- vapply(reachable_valid, function(id) score_fn(board, id), numeric(1))
      return(list(type = "build_settlement",
                  intersection_id = reachable_valid[which.max(scores)]))
    }
  }

  # 5. Buy dev card.
  if (can_build(player, "dev_card") && game_state$deck_size > 0L) {
    return(list(type = "buy_dev_card"))
  }

  # 6. Build road only if it opens a new settlement spot.
  if (can_build(player, "road")) {
    target <- best_settlement_target(board, player, score_fn, taken_ids)
    if (!is.na(target)) {
      reachable_now <- reachable_intersections(board, player, depth = 0L)
      if (!(target %in% reachable_now)) {
        eid <- road_toward(board, player, target)
        if (!is.na(eid)) return(list(type = "build_road", edge_id = eid))
      }
    }
  }

  list(type = "done")
}


# Helper: dev card play logic for ore_grain_strategy.
og_play_dev_card <- function(board, player, game_state) {
  # Play Knight for large-hand avoidance or Largest Army chase.
  if (can_play_dev_card(player, "knight")) {
    if (count_resources(player) >= 8L || player$knights_played >= 2L) {
      hex_id    <- choose_robber_placement(board, player, game_state$players)
      victim_id <- choose_steal_victim(board, player, game_state$players, hex_id)
      return(list(type = "play_knight", hex_id = hex_id, victim_id = victim_id))
    }
  }

  # Year of Plenty: take two resources toward the next city.
  if (can_play_dev_card(player, "year_of_plenty")) {
    cost   <- BUILD_COSTS[["city"]]
    needed <- names(which(cost > player$resources[names(cost)]))
    if (length(needed) >= 1L) {
      r1 <- needed[1]
      r2 <- if (length(needed) >= 2L) needed[2] else needed[1]
      return(list(type = "play_year_of_plenty", res1 = r1, res2 = r2))
    }
  }

  # Monopoly: take the resource most needed for cities.
  if (can_play_dev_card(player, "monopoly")) {
    cost  <- BUILD_COSTS[["city"]]
    gaps  <- pmax(cost - player$resources[names(cost)], 0L)
    if (sum(gaps) > 0L) {
      return(list(type = "play_monopoly",
                  resource = names(which.max(gaps))))
    }
  }

  NULL
}
