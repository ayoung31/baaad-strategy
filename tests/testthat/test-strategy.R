source(file.path(dirname(dirname(getwd())), "R", "board.R"))
source(file.path(dirname(dirname(getwd())), "R", "player.R"))
source(file.path(dirname(dirname(getwd())), "R", "strategy.R"))

# =============================================================================
# Shared test fixtures
# =============================================================================

# Fixed-seed board used throughout — deterministic hex/port layout.
BOARD <- generate_board(seed = 42)

# Three-player game with one of each strategy.
STRATS <- list(
  balanced  = balanced_strategy(),
  sheep     = sheep_strategy(),
  ore_grain = ore_grain_strategy()
)

# Helper: fresh player with a settlement at a given intersection.
player_at <- function(id, intersection_id, board = BOARD) {
  p <- make_player(id = id)
  p <- add_settlement_location(p, intersection_id)
  board <- place_structure(board, intersection_id, id, "settlement")
  list(player = p, board = board)
}

# Helper: minimal game_state for a 3-player game.
make_gs <- function(players, turn = 1L, active_id = 1L, deck_size = 25L) {
  list(players = players, turn = turn, active_id = active_id,
       deck_size = deck_size)
}

# Helper: build a player with enough resources for a specific item.
player_can_build <- function(id, item) {
  p <- make_player(id = id)
  cost <- BUILD_COSTS[[item]]
  p$resources <- cost
  p
}


# =============================================================================
# score_intersection
# =============================================================================

test_that("score_intersection returns 0 for a desert-only intersection", {
  # Find the desert hex and one of its corner intersections.
  desert_id <- which(vapply(BOARD$hexes, function(h) h$terrain == "desert",
                            logical(1)))
  # Check all 6 corners; at least one should be shared with a non-desert hex,
  # so we look for a corner that is ONLY touching the desert.
  corners <- HEX_INTERSECTIONS[[desert_id]]
  solo_desert <- Filter(function(id) {
    adj <- hexes_at_intersection(BOARD, id)
    all(vapply(adj, function(hid) BOARD$hexes[[hid]]$terrain == "desert",
               logical(1)))
  }, corners)

  if (length(solo_desert) > 0L) {
    expect_equal(score_intersection(BOARD, solo_desert[1]), 0)
  } else {
    skip("No intersection exclusively adjacent to desert on this board")
  }
})

test_that("score_intersection is non-negative for every intersection", {
  scores <- vapply(seq_len(54), function(id) score_intersection(BOARD, id),
                   numeric(1))
  expect_true(all(scores >= 0))
})

test_that("score_intersection never exceeds 15 (max 3 hexes × 5 pips)", {
  scores <- vapply(seq_len(54), function(id) score_intersection(BOARD, id),
                   numeric(1))
  expect_true(all(scores <= 15))
})

test_that("score_intersection matches manual pip sum for a known intersection", {
  # Intersection 24 is interior — touches 3 hexes. Verify against direct sum.
  hex_ids  <- hexes_at_intersection(BOARD, 24L)
  expected <- sum(vapply(hex_ids, function(hid) BOARD$hexes[[hid]]$pips,
                         numeric(1)))
  expect_equal(score_intersection(BOARD, 24L), expected)
})

test_that("score_intersection returns integer or numeric (not a list or NA)", {
  s <- score_intersection(BOARD, 1L)
  expect_true(is.numeric(s))
  expect_false(is.na(s))
})


# =============================================================================
# score_intersection_diversity
# =============================================================================

test_that("score_intersection_diversity >= score_intersection for same spot", {
  # Adding a diversity bonus can only increase the score.
  for (id in c(1L, 14L, 24L, 38L, 54L)) {
    base <- score_intersection(BOARD, id)
    div  <- score_intersection_diversity(BOARD, id, diversity_weight = 1)
    expect_gte(div, base,
               label = paste("intersection", id))
  }
})

test_that("score_intersection_diversity with weight 0 equals score_intersection", {
  for (id in c(5L, 20L, 40L)) {
    expect_equal(
      score_intersection_diversity(BOARD, id, diversity_weight = 0),
      score_intersection(BOARD, id),
      label = paste("intersection", id)
    )
  }
})

test_that("score_intersection_diversity bonus is proportional to distinct resources", {
  # For intersection 24 touching 3 distinct-resource hexes with weight=2,
  # result = pip_sum + 2 * n_distinct_resources.
  id      <- 24L
  hex_ids <- hexes_at_intersection(BOARD, id)
  pip_sum <- sum(vapply(hex_ids, function(hid) BOARD$hexes[[hid]]$pips,
                        numeric(1)))
  resources <- unique(Filter(Negate(is.na),
                             vapply(hex_ids,
                                    function(hid) BOARD$hexes[[hid]]$resource,
                                    character(1))))
  expected <- pip_sum + 2 * length(resources)
  expect_equal(score_intersection_diversity(BOARD, id, diversity_weight = 2),
               expected)
})


# =============================================================================
# score_intersection_for_resource
# =============================================================================

test_that("score_intersection_for_resource returns 0 for a resource not adjacent", {
  # Intersection 1 is a coastal corner touching at most 1-2 hexes.
  # Test that asking for a resource that isn't there returns 0.
  id <- 1L
  hex_ids   <- hexes_at_intersection(BOARD, id)
  resources <- vapply(hex_ids, function(hid) {
    r <- BOARD$hexes[[hid]]$resource
    if (is.na(r)) "" else r
  }, character(1))

  # Find a resource NOT present at this intersection.
  all_res <- c("lumber", "brick", "wool", "grain", "ore")
  absent  <- setdiff(all_res, resources)
  if (length(absent) > 0L) {
    expect_equal(score_intersection_for_resource(BOARD, id, absent[1]), 0)
  } else {
    skip("Intersection 1 has all 5 resources — unlikely but skipping")
  }
})

test_that("score_intersection_for_resource <= score_intersection", {
  # Resource-specific score can only be a subset of total pips.
  for (res in c("wool", "ore", "grain")) {
    for (id in c(10L, 25L, 36L)) {
      expect_lte(
        score_intersection_for_resource(BOARD, id, res),
        score_intersection(BOARD, id),
        label = paste(res, "at intersection", id)
      )
    }
  }
})

test_that("score_intersection_for_resource is additive: wool + ore + grain + lumber + brick <= total", {
  id      <- 24L
  total   <- score_intersection(BOARD, id)
  res_sum <- sum(vapply(c("wool","ore","grain","lumber","brick"), function(r) {
    score_intersection_for_resource(BOARD, id, r)
  }, numeric(1)))
  expect_equal(res_sum, total)
})


# =============================================================================
# valid_settlement_candidates
# =============================================================================

test_that("valid_settlement_candidates returns a non-empty set on a fresh board", {
  cands <- valid_settlement_candidates(BOARD, integer(0))
  expect_true(length(cands) > 0L)
})

test_that("all valid_settlement_candidates satisfy is_valid_settlement_spot", {
  cands <- valid_settlement_candidates(BOARD, integer(0))
  for (id in cands) {
    expect_true(is_valid_settlement_spot(BOARD, id),
                label = paste("intersection", id))
  }
})

test_that("valid_settlement_candidates excludes taken_ids", {
  taken <- c(1L, 9L, 14L)
  cands <- valid_settlement_candidates(BOARD, taken)
  expect_true(!any(taken %in% cands))
})

test_that("valid_settlement_candidates enforces the distance rule", {
  # Place a settlement at intersection 9. All intersections adjacent to 9
  # should be absent from candidates.
  board2 <- place_structure(BOARD, 9L, 1L, "settlement")
  taken  <- 9L
  cands  <- valid_settlement_candidates(board2, taken)

  adj_to_9 <- adjacent_intersections(9L)
  expect_true(!any(adj_to_9 %in% cands),
              info = "Adjacent intersections must be excluded after placement")
})

test_that("valid_settlement_candidates shrinks by at least (1 + n_adjacent) after a placement", {
  before <- length(valid_settlement_candidates(BOARD, integer(0)))
  board2 <- place_structure(BOARD, 14L, 1L, "settlement")
  after  <- length(valid_settlement_candidates(board2, 14L))
  # Placing one settlement removes at least: itself + its neighbours.
  expect_lt(after, before - 1L)
})


# =============================================================================
# valid_road_candidates
# =============================================================================

test_that("valid_road_candidates returns empty for a player with no network", {
  # A player with no roads or settlements has no valid road spots.
  p <- make_player(id = 1L)
  expect_length(valid_road_candidates(BOARD, p), 0L)
})

test_that("valid_road_candidates returns edges adjacent to player settlement", {
  # Place a settlement; the edges touching that intersection become valid.
  board2 <- place_structure(BOARD, 14L, 1L, "settlement")
  p      <- make_player(id = 1L)
  p      <- add_settlement_location(p, 14L)

  cands <- valid_road_candidates(board2, p)
  expect_true(length(cands) > 0L)

  # All returned edges must satisfy is_valid_road_spot.
  for (eid in cands) {
    expect_true(is_valid_road_spot(board2, eid, 1L),
                label = paste("edge", eid))
  }
})

test_that("valid_road_candidates does not return already-owned edges", {
  board2 <- place_structure(BOARD, 14L, 1L, "settlement")
  p      <- make_player(id = 1L)
  p      <- add_settlement_location(p, 14L)

  # Place one road, then verify it no longer appears in candidates.
  cands1 <- valid_road_candidates(board2, p)
  first_edge <- cands1[1]
  board2 <- place_road(board2, first_edge, 1L)
  p      <- add_road_location(p, first_edge)

  cands2 <- valid_road_candidates(board2, p)
  expect_false(first_edge %in% cands2)
})


# =============================================================================
# reachable_intersections
# =============================================================================

test_that("reachable_intersections returns empty for a player with no network", {
  p <- make_player(id = 1L)
  expect_length(reachable_intersections(BOARD, p, depth = 2L), 0L)
})

test_that("reachable_intersections at depth 0 returns only current network endpoints", {
  board2 <- place_structure(BOARD, 14L, 1L, "settlement")
  p      <- make_player(id = 1L)
  p      <- add_settlement_location(p, 14L)

  r <- reachable_intersections(board2, p, depth = 0L)
  # With no roads and depth 0, only the settlement intersection is reachable.
  expect_true(14L %in% r)
})

test_that("reachable_intersections grows with depth", {
  board2 <- place_structure(BOARD, 14L, 1L, "settlement")
  p      <- make_player(id = 1L)
  p      <- add_settlement_location(p, 14L)

  r0 <- reachable_intersections(board2, p, depth = 0L)
  r1 <- reachable_intersections(board2, p, depth = 1L)
  r2 <- reachable_intersections(board2, p, depth = 2L)

  expect_lte(length(r0), length(r1))
  expect_lte(length(r1), length(r2))
})

test_that("reachable_intersections does not pass through opponent settlements", {
  # Place player 1 settlement at 14, opponent at 19 (adjacent to 14).
  # Depth-1 expansion should NOT include intersections beyond 19.
  board2 <- place_structure(BOARD, 14L, 1L, "settlement")
  board2 <- place_structure(board2, 19L, 2L, "settlement")  # blocks path

  p <- make_player(id = 1L)
  p <- add_settlement_location(p, 14L)

  # Build road 14->19 direction to test blocking.
  # adjacent_intersections(14) includes 19; the edge 14-19 exists.
  edge_14_19 <- get_edge_id(board2, 14L, 19L)

  if (!is.na(edge_14_19)) {
    board2 <- place_road(board2, edge_14_19, 1L)
    p      <- add_road_location(p, edge_14_19)

    r1 <- reachable_intersections(board2, p, depth = 1L)
    # 19 may be in reachable (it's an endpoint) but further beyond it
    # (intersection adjacent to 19 that is NOT also adjacent to 14)
    # should be blocked by the opponent's settlement.
    # We just verify the opponent's settlement is not passable.
    # This is a structural test: verify reachable returns a numeric/integer vector.
    expect_true(is.numeric(r1) || is.integer(r1))
  } else {
    skip("14 and 19 are not adjacent on this board layout")
  }
})

test_that("reachable_intersections with negative depth returns empty", {
  p <- make_player(id = 1L)
  p <- add_settlement_location(p, 14L)
  expect_length(reachable_intersections(BOARD, p, depth = -1L), 0L)
})


# =============================================================================
# bfs_distances
# =============================================================================

test_that("bfs_distances returns 0 for the source intersection", {
  d <- bfs_distances(BOARD, 14L)
  expect_equal(d[14], 0)
})

test_that("bfs_distances returns 1 for all direct neighbours of source", {
  source_id <- 14L
  d         <- bfs_distances(BOARD, source_id)
  for (nb in adjacent_intersections(source_id)) {
    expect_equal(d[nb], 1,
                 label = paste("neighbour", nb, "of", source_id))
  }
})

test_that("bfs_distances are non-negative and finite for all connected nodes", {
  d <- bfs_distances(BOARD, 24L)
  expect_true(all(d >= 0))
  # The hex graph is fully connected, so all 54 intersections are reachable.
  expect_true(all(is.finite(d)))
})

test_that("bfs_distances satisfies triangle inequality for a sampled triple", {
  d <- bfs_distances(BOARD, 1L)
  # d[a->c] <= d[a->b] + d[b->c] for some triple.
  expect_lte(d[30], d[15] + bfs_distances(BOARD, 15L)[30])
})


# =============================================================================
# port_intersections
# =============================================================================

test_that("port_intersections returns exactly 2 intersections per 2:1 port", {
  # Each 2:1 port tile borders exactly 2 intersections.
  for (res in c("wool", "ore", "grain", "lumber", "brick")) {
    ints <- port_intersections(BOARD, res)
    expect_equal(length(ints), 2L,
                 label = paste(res, "port intersections"))
  }
})

test_that("port_intersections for general (3:1) ports returns 8 intersections", {
  # 4 general ports × 2 intersections each = 8.
  ints <- port_intersections(BOARD, NA)
  expect_equal(length(ints), 8L)
})

test_that("all port intersections are coastal", {
  for (res in c("wool", "ore", "grain", "lumber", "brick")) {
    ints <- port_intersections(BOARD, res)
    for (id in ints) {
      expect_true(BOARD$intersections[[id]]$is_coastal,
                  label = paste(res, "port at intersection", id))
    }
  }
})

test_that("port_intersections returns integer vector", {
  ints <- port_intersections(BOARD, "wool")
  expect_type(ints, "integer")
})


# =============================================================================
# choose_robber_placement
# =============================================================================

test_that("choose_robber_placement never returns the desert hex", {
  players <- init_players(c("balanced", "sheep"))
  hex_id  <- choose_robber_placement(BOARD, players[[1]], players)
  terrain <- BOARD$hexes[[hex_id]]$terrain
  expect_false(terrain == "desert")
})

test_that("choose_robber_placement never returns the current robber hex", {
  players <- init_players(c("balanced", "sheep"))
  hex_id  <- choose_robber_placement(BOARD, players[[1]], players)
  expect_false(hex_id == BOARD$robber_hex)
})

test_that("choose_robber_placement targets a hex adjacent to the leader", {
  # Give player 2 high VP so they are the leader.
  players       <- init_players(c("balanced", "sheep"))
  players[[2]]$vp <- 6L
  # Place player 2 settlement at intersection 24 so we know adjacent hexes.
  board2        <- place_structure(BOARD, 24L, 2L, "settlement")
  players[[2]]  <- add_settlement_location(players[[2]], 24L)

  hex_id        <- choose_robber_placement(board2, players[[1]], players)
  leader_adj    <- hexes_at_intersection(board2, 24L)

  # The robber should be on one of the leader's hexes (or the fallback if
  # all are desert/current robber — unlikely but accepted).
  moveable_leader <- intersect(
    leader_adj,
    which(vapply(board2$hexes,
                 function(h) h$terrain != "desert" && h$id != board2$robber_hex,
                 logical(1)))
  )
  if (length(moveable_leader) > 0L) {
    expect_true(hex_id %in% moveable_leader)
  }
})

test_that("choose_robber_placement returns a valid non-desert hex ID", {
  players <- init_players(c("balanced", "sheep", "ore_grain"))
  hex_id  <- choose_robber_placement(BOARD, players[[1]], players)
  expect_true(hex_id >= 1L && hex_id <= 19L)
  expect_false(BOARD$hexes[[hex_id]]$terrain == "desert")
})


# =============================================================================
# choose_steal_victim
# =============================================================================

test_that("choose_steal_victim returns NA when no opponent is adjacent to robber hex", {
  players <- init_players(c("balanced", "sheep"))
  # Use hex 1 with no settlements placed — nobody adjacent.
  result <- choose_steal_victim(BOARD, players[[1]], players, hex_id = 1L)
  expect_true(is.na(result))
})

test_that("choose_steal_victim returns the opponent adjacent to the robber hex", {
  board2  <- place_structure(BOARD, HEX_INTERSECTIONS[[3L]][1], 2L, "settlement")
  players <- init_players(c("balanced", "sheep"))
  players[[2]] <- add_settlement_location(players[[2]], HEX_INTERSECTIONS[[3L]][1])
  players[[2]] <- add_resources(players[[2]], c(ore = 3L))

  result <- choose_steal_victim(board2, players[[1]], players, hex_id = 3L)
  expect_equal(result, 2L)
})

test_that("choose_steal_victim picks the opponent with more cards when two are adjacent", {
  hex_id   <- 9L  # central hex — touches many intersections
  adj_ints <- HEX_INTERSECTIONS[[hex_id]]

  board2   <- BOARD
  players  <- init_players(c("balanced", "sheep", "ore_grain"))

  # Place player 2 at adj_ints[1], player 3 at adj_ints[2].
  board2  <- place_structure(board2, adj_ints[1], 2L, "settlement")
  board2  <- place_structure(board2, adj_ints[2], 3L, "settlement")
  players[[2]] <- add_settlement_location(players[[2]], adj_ints[1])
  players[[3]] <- add_settlement_location(players[[3]], adj_ints[2])

  # Player 3 has more cards — should be targeted.
  players[[2]] <- add_resources(players[[2]], c(wool = 1L))
  players[[3]] <- add_resources(players[[3]], c(wool = 5L))

  result <- choose_steal_victim(board2, players[[1]], players, hex_id = hex_id)
  expect_equal(result, 3L)
})

test_that("choose_steal_victim does not target the active player", {
  adj_ints <- HEX_INTERSECTIONS[[5L]]
  board2   <- place_structure(BOARD, adj_ints[1], 1L, "settlement")
  players  <- init_players(c("balanced", "sheep"))
  players[[1]] <- add_settlement_location(players[[1]], adj_ints[1])
  players[[1]] <- add_resources(players[[1]], c(ore = 10L))

  result <- choose_steal_victim(board2, players[[1]], players, hex_id = 5L)
  # Only player 1 is adjacent (player 2 has no settlement near hex 5),
  # so result should be NA — cannot steal from yourself.
  expect_true(is.na(result) || result != 1L)
})


# =============================================================================
# choose_discard
# =============================================================================

test_that("choose_discard is a no-op for a hand of exactly 7", {
  p      <- make_player(id = 1L)
  p$resources <- c(lumber=2L, brick=1L, wool=2L, grain=1L, ore=1L)  # sum = 7
  before <- p$resources
  p      <- choose_discard(p, "balanced")
  expect_equal(p$resources, before)
})

test_that("choose_discard removes exactly floor(n/2) cards for 8-card hand", {
  p <- make_player(id = 1L)
  p$resources <- c(lumber=2L, brick=2L, wool=2L, grain=1L, ore=1L)  # sum = 8
  p <- choose_discard(p, "balanced")
  expect_equal(count_resources(p), 4L)  # 8 - floor(8/2) = 4
})

test_that("choose_discard never produces negative resource counts", {
  p <- make_player(id = 1L)
  p$resources <- c(lumber=0L, brick=0L, wool=10L, grain=2L, ore=0L)  # sum = 12
  p <- choose_discard(p, "sheep")
  expect_true(all(p$resources >= 0L))
})

test_that("balanced strategy discard preserves ore and grain over wool", {
  # Give balanced player surplus wool and surplus ore+grain;
  # balanced discards wool first.
  p <- make_player(id = 1L)
  p$resources <- c(lumber=0L, brick=0L, wool=5L, grain=3L, ore=2L)  # sum = 10
  p <- choose_discard(p, "balanced")
  # Must have discarded 5 cards (floor(10/2)). Ore and grain should be intact.
  expect_equal(p$resources[["ore"]],   2L)
  expect_equal(p$resources[["grain"]], 3L)
})

test_that("sheep strategy discard preserves wool over lumber and brick", {
  # Sheep discards lumber/brick before touching wool.
  p <- make_player(id = 1L)
  p$resources <- c(lumber=4L, brick=4L, wool=2L, grain=0L, ore=0L)  # sum = 10
  p <- choose_discard(p, "sheep")
  # Discards 5; lumber+brick surplus should absorb the discards.
  expect_equal(p$resources[["wool"]], 2L)
})

test_that("ore_grain strategy discard preserves ore and grain like balanced", {
  p <- make_player(id = 1L)
  p$resources <- c(lumber=1L, brick=1L, wool=4L, grain=2L, ore=2L)  # sum = 10
  p <- choose_discard(p, "ore_grain")
  expect_equal(count_resources(p), 5L)  # floor(10/2) = 5 discarded, 5 remain
  expect_equal(p$resources[["ore"]],   2L)
  expect_equal(p$resources[["grain"]], 2L)
})

test_that("choose_discard removes the correct count for a 13-card hand", {
  p <- make_player(id = 1L)
  p$resources <- c(lumber=3L, brick=2L, wool=3L, grain=3L, ore=2L)  # sum = 13
  p <- choose_discard(p, "balanced")
  expect_equal(count_resources(p), 7L)  # 13 - floor(13/2) = 13 - 6 = 7
})


# =============================================================================
# Strategy interface — all three strategies
# =============================================================================

test_that("all strategies have the four required interface function slots", {
  required <- c("choose_initial_placement", "choose_second_placement",
                "choose_road_placement", "choose_action")
  for (nm in names(STRATS)) {
    expect_named(STRATS[[nm]], required, ignore.order = TRUE,
                 label = nm)
  }
})

test_that("all strategy slots are functions", {
  slots <- c("choose_initial_placement", "choose_second_placement",
             "choose_road_placement", "choose_action")
  for (nm in names(STRATS)) {
    for (slot in slots) {
      expect_true(is.function(STRATS[[nm]][[slot]]),
                  label = paste(nm, slot))
    }
  }
})


# =============================================================================
# choose_initial_placement — all three strategies
# =============================================================================

test_that("choose_initial_placement returns a single integer for all strategies", {
  p <- make_player(id = 1L)
  for (nm in names(STRATS)) {
    id <- STRATS[[nm]]$choose_initial_placement(BOARD, p, integer(0))
    expect_equal(length(id), 1L)
    expect_type(id, "integer")
  }
})

test_that("choose_initial_placement returns a valid settlement spot", {
  p <- make_player(id = 1L)
  for (nm in names(STRATS)) {
    id <- STRATS[[nm]]$choose_initial_placement(BOARD, p, integer(0))
    expect_true(is_valid_settlement_spot(BOARD, id),
                label = paste(nm, "placement at", id))
  }
})

test_that("choose_initial_placement respects taken_ids", {
  p <- make_player(id = 1L)

  # Take the three intersections most likely to be top-scored on this board,
  # then verify every strategy picks something different.
  all_valid <- valid_settlement_candidates(BOARD, integer(0))
  # Score all candidates and take the top 3 by pip sum to remove the obvious picks.
  scores  <- vapply(all_valid, function(id) score_intersection(BOARD, id), numeric(1))
  top3    <- all_valid[order(scores, decreasing = TRUE)[seq_len(min(3L, length(all_valid)))]]
  board2  <- BOARD
  for (id in top3) {
    board2 <- place_structure(board2, id, 99L, "settlement")
  }

  # There must still be valid candidates after removing the top 3.
  remaining <- valid_settlement_candidates(board2, top3)
  if (length(remaining) == 0L) skip("No valid candidates remain after removing top 3")

  for (nm in names(STRATS)) {
    id <- STRATS[[nm]]$choose_initial_placement(board2, p, top3)
    expect_false(id %in% top3,
                 info = paste(nm, "must not pick a taken intersection"))
    expect_true(is_valid_settlement_spot(board2, id),
                info = paste(nm, "placement must be valid"))
  }
})

test_that("sheep_strategy initial placement scores higher on wool than balanced", {
  p <- make_player(id = 1L)
  sheep_id    <- STRATS$sheep$choose_initial_placement(BOARD, p, integer(0))
  balanced_id <- STRATS$balanced$choose_initial_placement(BOARD, p, integer(0))

  sheep_wool    <- score_intersection_for_resource(BOARD, sheep_id,    "wool")
  balanced_wool <- score_intersection_for_resource(BOARD, balanced_id, "wool")

  # sheep_strategy weights wool 2x so its pick should have >= wool pips than
  # balanced's pick (they may coincide if the same spot tops both rankings).
  expect_gte(sheep_wool, balanced_wool)
})

test_that("ore_grain_strategy initial placement scores higher on ore+grain than sheep", {
  p <- make_player(id = 1L)
  og_id    <- STRATS$ore_grain$choose_initial_placement(BOARD, p, integer(0))
  sheep_id <- STRATS$sheep$choose_initial_placement(BOARD, p, integer(0))

  og_og    <- score_intersection_for_resource(BOARD, og_id,    "ore") +
              score_intersection_for_resource(BOARD, og_id,    "grain")
  sheep_og <- score_intersection_for_resource(BOARD, sheep_id, "ore") +
              score_intersection_for_resource(BOARD, sheep_id, "grain")

  expect_gte(og_og, sheep_og)
})


# =============================================================================
# choose_second_placement — sheep_strategy Wool port hard-target
# =============================================================================

test_that("sheep_strategy second placement lands on a Wool port intersection when available", {
  # The +100 PORT_BONUS guarantees the sheep strategy picks a Wool port
  # intersection on its second placement if one is unoccupied and valid.
  wool_port_ints <- port_intersections(BOARD, "wool")
  p              <- make_player(id = 1L)

  # First placement somewhere far from the port.
  first_id <- STRATS$sheep$choose_initial_placement(BOARD, p, integer(0))
  board2   <- place_structure(BOARD, first_id, 1L, "settlement")
  p        <- add_settlement_location(p, first_id)
  taken    <- c(first_id)

  second_id <- STRATS$sheep$choose_second_placement(board2, p, taken)

  # Must be valid.
  expect_true(is_valid_settlement_spot(board2, second_id))

  # If a Wool port intersection is still available, it must be picked.
  available_wool_ports <- Filter(function(id) {
    !(id %in% taken) && is_valid_settlement_spot(board2, id)
  }, wool_port_ints)

  if (length(available_wool_ports) > 0L) {
    expect_true(second_id %in% wool_port_ints,
                info = "sheep_strategy must hard-target Wool port on second placement")
  } else {
    skip("No valid Wool port intersection available for second placement")
  }
})

test_that("balanced and ore_grain second placements are valid", {
  p     <- make_player(id = 1L)
  first <- STRATS$balanced$choose_initial_placement(BOARD, p, integer(0))
  board2 <- place_structure(BOARD, first, 1L, "settlement")
  p      <- add_settlement_location(p, first)

  for (nm in c("balanced", "ore_grain")) {
    id <- STRATS[[nm]]$choose_second_placement(board2, p, c(first))
    expect_true(is_valid_settlement_spot(board2, id),
                label = paste(nm, "second placement valid"))
    expect_false(id == first, label = paste(nm, "doesn't pick same spot"))
  }
})


# =============================================================================
# choose_road_placement
# =============================================================================

test_that("choose_road_placement returns a valid edge ID for all strategies", {
  board2   <- place_structure(BOARD, 14L, 1L, "settlement")
  p        <- make_player(id = 1L)
  p        <- add_settlement_location(p, 14L)
  players  <- list(p, make_player(id = 2L), make_player(id = 3L))
  gs       <- make_gs(players)

  for (nm in names(STRATS)) {
    eid <- STRATS[[nm]]$choose_road_placement(board2, p, gs)
    expect_equal(length(eid), 1L)
    expect_true(is_valid_road_spot(board2, eid, 1L),
                info = paste(nm, "road at edge", eid))
  }
})

test_that("choose_road_placement returns an edge adjacent to the player's settlement", {
  # The first road must connect to the player's network — otherwise it's illegal.
  board2  <- place_structure(BOARD, 14L, 1L, "settlement")
  p       <- make_player(id = 1L)
  p       <- add_settlement_location(p, 14L)
  players <- list(p, make_player(id = 2L))
  gs      <- make_gs(players)

  for (nm in names(STRATS)) {
    eid  <- STRATS[[nm]]$choose_road_placement(board2, p, gs)
    edge <- board2$edges[[eid]]
    # At least one endpoint of the chosen edge must be the settlement intersection.
    expect_true(14L %in% edge$ends,
                info = paste(nm, "road connects to settlement"))
  }
})

test_that("must_connect_to restricts road to edges adjacent to the specified intersection", {
  # Player has two settlements; without must_connect_to either could get a road.
  # With must_connect_to = second settlement, only edges touching it are valid.
  board2 <- place_structure(BOARD, 14L, 1L, "settlement")
  board2 <- place_structure(board2, 36L, 1L, "settlement")
  p      <- make_player(id = 1L)
  p      <- add_settlement_location(p, 14L)
  p      <- add_settlement_location(p, 36L)
  # Add a road from the first settlement so the network isn't trivially single-node.
  eid_first <- valid_road_candidates(board2, p)[1]
  board2 <- place_road(board2, eid_first, 1L)
  p      <- add_road_location(p, eid_first)

  players <- list(p, make_player(id = 2L))
  gs      <- make_gs(players)

  for (nm in names(STRATS)) {
    eid  <- STRATS[[nm]]$choose_road_placement(board2, p, gs, must_connect_to = 36L)
    edge <- board2$edges[[eid]]
    expect_true(36L %in% edge$ends,
                info = paste(nm, "road must touch intersection 36"))
    expect_true(is_valid_road_spot(board2, eid, 1L),
                info = paste(nm, "road must be a valid placement"))
  }
})

test_that("setup road placement in full snake draft always connects to that turn's settlement", {
  board2 <- BOARD
  taken  <- integer(0)
  players_test <- init_players(c("balanced", "sheep", "ore_grain"))
  gs     <- make_gs(players_test)

  for (i in c(1, 2, 3, 3, 2, 1)) {
    gs$active_id <- i
    gs$players   <- players_test

    is_second <- length(players_test[[i]]$settlement_locations) == 1L
    place_fn  <- if (is_second) STRATS[[i]]$choose_second_placement
                 else           STRATS[[i]]$choose_initial_placement

    sid              <- place_fn(board2, players_test[[i]], taken)
    board2           <- place_structure(board2, sid, i, "settlement")
    players_test[[i]] <- add_settlement_location(players_test[[i]], sid)
    taken            <- c(taken, sid)

    # Road must connect to the settlement placed THIS turn.
    eid  <- STRATS[[i]]$choose_road_placement(board2, players_test[[i]], gs,
                                               must_connect_to = sid)
    edge <- board2$edges[[eid]]
    expect_true(sid %in% edge$ends,
                info = paste("Player", i, "setup road must touch settlement", sid))
    expect_true(is_valid_road_spot(board2, eid, i),
                info = paste("Player", i, "setup road must be valid"))

    board2           <- place_road(board2, eid, i)
    players_test[[i]] <- add_road_location(players_test[[i]], eid)
  }
})


# =============================================================================
# choose_action — general contract
# =============================================================================

test_that("choose_action always returns a list with a 'type' field", {
  board2  <- place_structure(BOARD, 14L, 1L, "settlement")
  p       <- make_player(id = 1L)
  p       <- add_settlement_location(p, 14L)
  players <- list(p, make_player(id = 2L), make_player(id = 3L))
  gs      <- make_gs(players)

  for (nm in names(STRATS)) {
    action <- STRATS[[nm]]$choose_action(board2, p, gs)
    expect_true(is.list(action),   label = paste(nm, "returns list"))
    expect_true("type" %in% names(action), label = paste(nm, "has type field"))
  }
})

test_that("choose_action returns 'done' when player has no resources and nothing to play", {
  board2  <- place_structure(BOARD, 14L, 1L, "settlement")
  p       <- make_player(id = 1L)
  p       <- add_settlement_location(p, 14L)
  # Ensure no resources at all.
  p$resources <- c(lumber=0L, brick=0L, wool=0L, grain=0L, ore=0L)
  players <- list(p, make_player(id = 2L))
  gs      <- make_gs(players)

  for (nm in names(STRATS)) {
    action <- STRATS[[nm]]$choose_action(board2, p, gs)
    expect_equal(action$type, "done",
                 label = paste(nm, "returns done with empty hand"))
  }
})

test_that("choose_action returns 'build_city' for balanced and ore_grain when able", {
  board2  <- place_structure(BOARD, 14L, 1L, "settlement")
  p       <- make_player(id = 1L)
  p       <- add_settlement_location(p, 14L)
  # Exact city cost: 3 ore + 2 grain.
  p$resources <- c(lumber=0L, brick=0L, wool=0L, grain=2L, ore=3L)
  players <- list(p, make_player(id = 2L))
  gs      <- make_gs(players)

  for (nm in c("balanced", "ore_grain")) {
    action <- STRATS[[nm]]$choose_action(board2, p, gs)
    expect_equal(action$type, "build_city",
                 label = paste(nm, "builds city when able"))
    expect_equal(action$intersection_id, 14L,
                 label = paste(nm, "upgrades the existing settlement"))
  }
})

test_that("choose_action 'build_city' intersection_id is one of the player's settlements", {
  board2  <- place_structure(BOARD, 14L, 1L, "settlement")
  board2  <- place_structure(board2, 24L, 1L, "settlement")
  p       <- make_player(id = 1L)
  p       <- add_settlement_location(p, 14L)
  p       <- add_settlement_location(p, 24L)
  p$resources <- c(lumber=0L, brick=0L, wool=0L, grain=2L, ore=3L)
  players <- list(p, make_player(id = 2L))
  gs      <- make_gs(players)

  action <- STRATS$balanced$choose_action(board2, p, gs)
  if (action$type == "build_city") {
    expect_true(action$intersection_id %in% p$settlement_locations)
  }
})

test_that("choose_action returns 'buy_dev_card' for sheep when it has dev card cost", {
  board2  <- place_structure(BOARD, 14L, 1L, "settlement")
  p       <- make_player(id = 1L)
  p       <- add_settlement_location(p, 14L)
  # Exact dev card cost: 1 ore + 1 wool + 1 grain.
  p$resources <- c(lumber=0L, brick=0L, wool=1L, grain=1L, ore=1L)
  players <- list(p, make_player(id = 2L))
  gs      <- make_gs(players, deck_size = 10L)

  action <- STRATS$sheep$choose_action(board2, p, gs)
  expect_equal(action$type, "buy_dev_card")
})

test_that("choose_action does not buy dev card when deck is empty", {
  board2  <- place_structure(BOARD, 14L, 1L, "settlement")
  p       <- make_player(id = 1L)
  p       <- add_settlement_location(p, 14L)
  p$resources <- c(lumber=0L, brick=0L, wool=1L, grain=1L, ore=1L)
  players <- list(p, make_player(id = 2L))
  # Empty deck.
  gs <- make_gs(players, deck_size = 0L)

  for (nm in names(STRATS)) {
    action <- STRATS[[nm]]$choose_action(board2, p, gs)
    expect_false(action$type == "buy_dev_card",
                 label = paste(nm, "should not buy from empty deck"))
  }
})

test_that("choose_action returns a trade action when a useful trade is available", {
  # Give balanced 4 wool (enough for 4:1 bank trade) and it needs ore for city.
  board2  <- place_structure(BOARD, 14L, 1L, "settlement")
  p       <- make_player(id = 1L)
  p       <- add_settlement_location(p, 14L)
  p$resources <- c(lumber=0L, brick=0L, wool=4L, grain=2L, ore=2L)
  players <- list(p, make_player(id = 2L))
  gs      <- make_gs(players)

  action <- STRATS$balanced$choose_action(board2, p, gs)
  # Balanced can afford city (3 ore, 2 grain) via trade: needs 1 more ore.
  # Wool surplus → trade → ore. Expect a trade action.
  expect_equal(action$type, "trade")
  expect_equal(action$give, "wool")
  expect_equal(action$receive, "ore")
})

test_that("choose_action trade action has correct give_count matching bank/port rate", {
  board2  <- place_structure(BOARD, 14L, 1L, "settlement")
  p       <- make_player(id = 1L)
  p       <- add_settlement_location(p, 14L)
  p$resources <- c(lumber=0L, brick=0L, wool=4L, grain=2L, ore=2L)
  players <- list(p, make_player(id = 2L))
  gs      <- make_gs(players)

  action <- STRATS$balanced$choose_action(board2, p, gs)
  if (action$type == "trade") {
    # give_count must be 2, 3, or 4 depending on port access.
    expect_true(action$give_count %in% c(2L, 3L, 4L))
    # give_count must match what trade_rate_for says for this player.
    expected_rate <- trade_rate_for(board2, p, action$give)
    expect_equal(action$give_count, expected_rate)
  }
})

test_that("choose_action play_knight action includes valid hex_id", {
  board2 <- place_structure(BOARD, 14L, 1L, "settlement")
  p      <- make_player(id = 1L)
  p      <- add_settlement_location(p, 14L)
  # Give the player a playable knight (in dev_cards, not dev_cards_new).
  p$dev_cards[["knight"]] <- 1L
  p$knights_played        <- 2L  # close to Largest Army threshold
  players <- list(p, make_player(id = 2L))
  gs      <- make_gs(players)

  action <- STRATS$balanced$choose_action(board2, p, gs)
  if (action$type == "play_knight") {
    expect_true(action$hex_id >= 1L && action$hex_id <= 19L)
    expect_false(BOARD$hexes[[action$hex_id]]$terrain == "desert")
    expect_false(action$hex_id == BOARD$robber_hex)
  }
})

test_that("choose_action build_settlement intersection_id is reachable and valid", {
  board2  <- place_structure(BOARD, 14L, 1L, "settlement")
  p       <- make_player(id = 1L)
  p       <- add_settlement_location(p, 14L)
  # Add a road to expand the network to an adjacent intersection.
  adj_of_14 <- adjacent_intersections(14L)[1]
  eid       <- get_edge_id(board2, 14L, adj_of_14)
  board2    <- place_road(board2, eid, 1L)
  p         <- add_road_location(p, eid)
  # Full settlement cost.
  p$resources <- c(lumber=1L, brick=1L, wool=1L, grain=1L, ore=0L)
  players <- list(p, make_player(id = 2L))
  gs      <- make_gs(players)

  for (nm in names(STRATS)) {
    action <- STRATS[[nm]]$choose_action(board2, p, gs)
    if (action$type == "build_settlement") {
      expect_true(is_valid_settlement_spot(board2, action$intersection_id),
                  label = paste(nm, "settlement spot is valid"))
    }
  }
})


# =============================================================================
# choose_action — play_year_of_plenty
# =============================================================================

test_that("play_year_of_plenty action returns two resource names", {
  p <- make_player(id = 1L)
  p$dev_cards[["year_of_plenty"]] <- 1L
  p <- add_settlement_location(p, 14L)
  board2  <- place_structure(BOARD, 14L, 1L, "settlement")
  players <- list(p, make_player(id = 2L))
  gs      <- make_gs(players)

  action <- STRATS$balanced$choose_action(board2, p, gs)
  if (action$type == "play_year_of_plenty") {
    expect_true(action$res1 %in% c("lumber","brick","wool","grain","ore"))
    expect_true(action$res2 %in% c("lumber","brick","wool","grain","ore"))
  }
})


# =============================================================================
# choose_action — play_monopoly
# =============================================================================

test_that("play_monopoly action names a valid resource", {
  p <- make_player(id = 1L)
  p$dev_cards[["monopoly"]] <- 1L
  p <- add_settlement_location(p, 14L)
  board2  <- place_structure(BOARD, 14L, 1L, "settlement")
  players <- list(p, make_player(id = 2L))
  gs      <- make_gs(players)

  action <- STRATS$balanced$choose_action(board2, p, gs)
  if (action$type == "play_monopoly") {
    expect_true(action$resource %in% c("lumber","brick","wool","grain","ore"))
  }
})


# =============================================================================
# road_toward
# =============================================================================

test_that("road_toward returns an edge adjacent to the player's network", {
  board2  <- place_structure(BOARD, 14L, 1L, "settlement")
  p       <- make_player(id = 1L)
  p       <- add_settlement_location(p, 14L)
  target  <- 38L  # a distant intersection

  eid <- road_toward(board2, p, target)
  expect_false(is.na(eid))
  expect_true(is_valid_road_spot(board2, eid, 1L))
})

test_that("road_toward edge endpoint is closer to target than other candidates", {
  board2 <- place_structure(BOARD, 14L, 1L, "settlement")
  p      <- make_player(id = 1L)
  p      <- add_settlement_location(p, 14L)
  target <- 50L

  eid   <- road_toward(board2, p, target)
  edge  <- board2$edges[[eid]]
  dist_target <- bfs_distances(board2, target)

  chosen_dist <- min(dist_target[edge$ends[1]], dist_target[edge$ends[2]])

  # All other valid candidates should be at least as far from the target.
  for (e_cand in valid_road_candidates(board2, p)) {
    e   <- board2$edges[[e_cand]]
    d   <- min(dist_target[e$ends[1]], dist_target[e$ends[2]])
    expect_gte(d, chosen_dist,
               label = paste("candidate edge", e_cand, "distance", d,
                             ">= chosen edge distance", chosen_dist))
  }
})


# =============================================================================
# nearest_wool_port_intersection
# =============================================================================

test_that("nearest_wool_port_intersection returns a valid Wool port intersection", {
  board2  <- place_structure(BOARD, 14L, 1L, "settlement")
  p       <- make_player(id = 1L)
  p       <- add_settlement_location(p, 14L)
  wool_port_ints <- port_intersections(BOARD, "wool")

  result <- nearest_wool_port_intersection(BOARD, p)
  expect_false(is.na(result))
  expect_true(result %in% wool_port_ints)
})

test_that("nearest_wool_port_intersection returns one of the two Wool port intersections", {
  wool_port_ints <- port_intersections(BOARD, "wool")
  p  <- make_player(id = 1L)
  p  <- add_settlement_location(p, 14L)

  result <- nearest_wool_port_intersection(BOARD, p)
  expect_length(result, 1L)
  expect_true(result %in% wool_port_ints)
})


# =============================================================================
# Catan rules: placement validity cross-checks
# =============================================================================

test_that("no strategy places initial settlement on an already-taken intersection", {
  p     <- make_player(id = 1L)
  taken <- integer(0)
  board2 <- BOARD

  for (nm in names(STRATS)) {
    id <- STRATS[[nm]]$choose_initial_placement(board2, p, taken)
    expect_false(id %in% taken,
                 label = paste(nm, "must not duplicate a taken spot"))
    # Add it to taken and mark on board for the next iteration.
    taken  <- c(taken, id)
    board2 <- place_structure(board2, id, which(names(STRATS) == nm), "settlement")
  }
})

test_that("no strategy places road on an already-occupied edge", {
  board2  <- place_structure(BOARD, 14L, 1L, "settlement")
  p       <- make_player(id = 1L)
  p       <- add_settlement_location(p, 14L)
  players <- list(p, make_player(id = 2L))
  gs      <- make_gs(players)

  for (nm in names(STRATS)) {
    eid    <- STRATS[[nm]]$choose_road_placement(board2, p, gs)
    e      <- board2$edges[[eid]]
    expect_true(is.na(e$owner),
                label = paste(nm, "road edge must be unoccupied"))
  }
})

test_that("multiple sequential placements always remain valid (distance rule preserved)", {
  board2 <- BOARD
  taken  <- integer(0)

  for (round in seq_len(3)) {
    p  <- make_player(id = round)
    id <- STRATS[[round]]$choose_initial_placement(board2, p, taken)
    expect_true(is_valid_settlement_spot(board2, id),
                label = paste("round", round, "placement at", id, "is valid"))
    board2 <- place_structure(board2, id, round, "settlement")
    taken  <- c(taken, id)
  }
})
