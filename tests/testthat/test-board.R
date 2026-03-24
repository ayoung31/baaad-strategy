source(file.path(dirname(dirname(getwd())), "R", "board.R"))

board <- generate_board(seed = 42)

# =============================================================================
# Structure
# =============================================================================

test_that("board has required top-level fields", {
  expect_named(board, c("hexes", "intersections", "edges", "robber_hex"),
               ignore.order = TRUE)
})

test_that("board has exactly 19 hexes", {
  expect_length(board$hexes, 19)
})

test_that("board has exactly 54 intersections", {
  expect_length(board$intersections, 54)
})

test_that("edges are a non-empty list", {
  expect_true(length(board$edges) > 0)
})

test_that("each hex has required fields", {
  required <- c("id", "terrain", "resource", "token", "pips", "has_robber")
  for (h in board$hexes) {
    expect_named(h, required, ignore.order = TRUE,
                 label = paste("hex", h$id))
  }
})

test_that("each intersection has required fields", {
  required <- c("id", "owner", "structure", "port", "is_coastal")
  for (int in board$intersections) {
    expect_named(int, required, ignore.order = TRUE,
                 label = paste("intersection", int$id))
  }
})

test_that("each edge has required fields", {
  required <- c("id", "ends", "owner")
  for (e in board$edges) {
    expect_named(e, required, ignore.order = TRUE,
                 label = paste("edge", e$id))
  }
})

# =============================================================================
# Hex terrain counts
# =============================================================================

test_that("terrain counts match the standard distribution", {
  terrains <- vapply(board$hexes, `[[`, character(1), "terrain")
  counts   <- table(terrains)
  expect_equal(as.integer(counts["forest"]),   4L)
  expect_equal(as.integer(counts["hills"]),    3L)
  expect_equal(as.integer(counts["pasture"]),  4L)
  expect_equal(as.integer(counts["fields"]),   4L)
  expect_equal(as.integer(counts["mountain"]), 3L)
  expect_equal(as.integer(counts["desert"]),   1L)
})

test_that("exactly one hex has terrain 'desert'", {
  terrains <- vapply(board$hexes, `[[`, character(1), "terrain")
  expect_equal(sum(terrains == "desert"), 1L)
})

# =============================================================================
# Number tokens
# =============================================================================

test_that("desert hex has NA token and 0 pips", {
  desert <- Filter(function(h) h$terrain == "desert", board$hexes)[[1]]
  expect_true(is.na(desert$token))
  expect_equal(desert$pips, 0L)
})

test_that("all non-desert hexes have a non-NA token", {
  non_desert <- Filter(function(h) h$terrain != "desert", board$hexes)
  tokens <- vapply(non_desert, `[[`, integer(1), "token")
  expect_false(anyNA(tokens))
})

test_that("number tokens across non-desert hexes match standard distribution", {
  non_desert <- Filter(function(h) h$terrain != "desert", board$hexes)
  tokens <- sort(vapply(non_desert, `[[`, integer(1), "token"))
  expect_equal(tokens, sort(NUMBER_TOKENS))
})

test_that("no hex has token 7", {
  tokens <- vapply(board$hexes, function(h) if (is.na(h$token)) -1L else h$token,
                   integer(1))
  expect_false(7L %in% tokens)
})

test_that("tokens are in range 2-12 (excluding 7) for non-desert hexes", {
  non_desert <- Filter(function(h) h$terrain != "desert", board$hexes)
  tokens <- vapply(non_desert, `[[`, integer(1), "token")
  expect_true(all(tokens >= 2 & tokens <= 12 & tokens != 7))
})

# =============================================================================
# Pip counts
# =============================================================================

test_that("pip counts match PIPS lookup for every non-desert hex", {
  for (h in board$hexes) {
    if (h$terrain == "desert") next
    expected_pips <- PIPS[[as.character(h$token)]]
    expect_equal(h$pips, expected_pips,
                 label = paste("pips for token", h$token, "on hex", h$id))
  }
})

test_that("tokens 6 and 8 have 5 pips", {
  for (h in board$hexes) {
    if (is.na(h$token)) next
    if (h$token %in% c(6L, 8L)) expect_equal(h$pips, 5L)
  }
})

test_that("tokens 2 and 12 have 1 pip", {
  for (h in board$hexes) {
    if (is.na(h$token)) next
    if (h$token %in% c(2L, 12L)) expect_equal(h$pips, 1L)
  }
})

# =============================================================================
# Terrain → resource mapping
# =============================================================================

test_that("terrain-to-resource mapping is correct for every hex", {
  for (h in board$hexes) {
    expect_equal(h$resource, TERRAIN_RESOURCE[[h$terrain]],
                 label = paste("resource for terrain", h$terrain, "hex", h$id))
  }
})

test_that("desert hex has NA resource", {
  desert <- Filter(function(h) h$terrain == "desert", board$hexes)[[1]]
  expect_true(is.na(desert$resource))
})

# =============================================================================
# Robber
# =============================================================================

test_that("robber starts on the desert hex", {
  desert_id <- which(vapply(board$hexes, function(h) h$terrain == "desert",
                            logical(1)))
  expect_equal(board$robber_hex, desert_id)
})

test_that("exactly one hex has has_robber == TRUE at start", {
  robber_flags <- vapply(board$hexes, `[[`, logical(1), "has_robber")
  expect_equal(sum(robber_flags), 1L)
})

test_that("the hex with has_robber is the desert", {
  robber_hex <- Filter(function(h) h$has_robber, board$hexes)[[1]]
  expect_equal(robber_hex$terrain, "desert")
})

# =============================================================================
# Intersections
# =============================================================================

test_that("all intersections start unoccupied (structure = 'none')", {
  structures <- vapply(board$intersections, `[[`, character(1), "structure")
  expect_true(all(structures == "none"))
})

test_that("all intersections start with owner = NA", {
  owners <- vapply(board$intersections, `[[`, integer(1), "owner")
  expect_true(all(is.na(owners)))
})

test_that("intersection IDs are sequential 1-54", {
  ids <- vapply(board$intersections, `[[`, integer(1), "id")
  expect_equal(ids, 1L:54L)
})

test_that("is_coastal flag matches COASTAL_INTERSECTIONS constant", {
  for (int in board$intersections) {
    expected <- int$id %in% COASTAL_INTERSECTIONS
    expect_equal(int$is_coastal, expected,
                 label = paste("is_coastal for intersection", int$id))
  }
})

test_that("exactly 30 intersections are coastal", {
  coastal_flags <- vapply(board$intersections, `[[`, logical(1), "is_coastal")
  expect_equal(sum(coastal_flags), length(COASTAL_INTERSECTIONS))
})

# =============================================================================
# Edges
# =============================================================================

test_that("edge IDs are sequential starting from 1", {
  ids <- vapply(board$edges, `[[`, integer(1), "id")
  expect_equal(ids, seq_along(board$edges))
})

test_that("all edge endpoints are valid intersection IDs (1-54)", {
  for (e in board$edges) {
    expect_true(all(e$ends >= 1L & e$ends <= 54L),
                label = paste("edge", e$id, "endpoints in range"))
  }
})

test_that("each edge connects two distinct intersections", {
  for (e in board$edges) {
    expect_false(e$ends[1] == e$ends[2],
                 label = paste("edge", e$id, "has distinct endpoints"))
  }
})

test_that("no duplicate edges", {
  edge_keys <- vapply(board$edges, function(e) {
    paste(sort(e$ends), collapse = "-")
  }, character(1))
  expect_equal(length(edge_keys), length(unique(edge_keys)))
})

test_that("all edges start unowned (owner = NA)", {
  owners <- vapply(board$edges, `[[`, integer(1), "owner")
  expect_true(all(is.na(owners)))
})

# =============================================================================
# Ports
# =============================================================================

test_that("exactly 18 intersections have ports (9 ports × 2 intersections)", {
  port_flags <- vapply(board$intersections,
                       function(i) !is.null(i$port), logical(1))
  expect_equal(sum(port_flags), 18L)
})

test_that("there are exactly 4 general (3:1) ports", {
  port_ints  <- Filter(function(i) !is.null(i$port), board$intersections)
  general    <- Filter(function(i) is.na(i$port$resource), port_ints)
  # Each port covers 2 intersections, so 4 ports = 8 intersections
  expect_equal(length(general), 8L)
})

test_that("there is exactly one of each specific 2:1 port", {
  port_ints <- Filter(function(i) !is.null(i$port), board$intersections)
  specific  <- Filter(function(i) !is.na(i$port$resource), port_ints)
  resources <- vapply(specific, function(i) i$port$resource, character(1))
  resource_counts <- table(resources)
  # Each specific port covers 2 intersections
  for (res in c("lumber", "brick", "wool", "grain", "ore")) {
    expect_equal(as.integer(resource_counts[res]), 2L,
                 label = paste("2:1 port count for", res))
  }
})

test_that("all port intersections are coastal", {
  for (int in board$intersections) {
    if (!is.null(int$port)) {
      expect_true(int$is_coastal,
                  label = paste("port intersection", int$id, "is coastal"))
    }
  }
})

test_that("port rates are either 2 or 3", {
  for (int in board$intersections) {
    if (!is.null(int$port)) {
      expect_true(int$port$rate %in% c(2L, 3L),
                  label = paste("port rate at intersection", int$id))
    }
  }
})

test_that("specific 2:1 ports have resources in RESOURCES", {
  for (int in board$intersections) {
    if (!is.null(int$port) && !is.na(int$port$resource)) {
      expect_true(int$port$resource %in% RESOURCES,
                  label = paste("port resource at intersection", int$id))
    }
  }
})

# =============================================================================
# Reproducibility and randomness
# =============================================================================

test_that("same seed produces identical boards", {
  b1 <- generate_board(seed = 99)
  b2 <- generate_board(seed = 99)
  terrains_1 <- vapply(b1$hexes, `[[`, character(1), "terrain")
  terrains_2 <- vapply(b2$hexes, `[[`, character(1), "terrain")
  expect_equal(terrains_1, terrains_2)
  tokens_1 <- vapply(b1$hexes, function(h) if (is.na(h$token)) -1L else h$token,
                     integer(1))
  tokens_2 <- vapply(b2$hexes, function(h) if (is.na(h$token)) -1L else h$token,
                     integer(1))
  expect_equal(tokens_1, tokens_2)
})

test_that("different seeds produce different terrain arrangements", {
  b1 <- generate_board(seed = 1)
  b2 <- generate_board(seed = 2)
  terrains_1 <- vapply(b1$hexes, `[[`, character(1), "terrain")
  terrains_2 <- vapply(b2$hexes, `[[`, character(1), "terrain")
  # Overwhelmingly likely to differ (1/19! chance of same arrangement)
  expect_false(identical(terrains_1, terrains_2))
})

test_that("fixed board (no randomness) is deterministic without a seed", {
  b1 <- generate_board(random_terrain = FALSE, random_tokens = FALSE)
  b2 <- generate_board(random_terrain = FALSE, random_tokens = FALSE)
  terrains_1 <- vapply(b1$hexes, `[[`, character(1), "terrain")
  terrains_2 <- vapply(b2$hexes, `[[`, character(1), "terrain")
  expect_equal(terrains_1, terrains_2)
})

# =============================================================================
# Query helpers
# =============================================================================

test_that("intersections_of_hex returns exactly 6 intersections per hex", {
  for (hex_id in 1:19) {
    ints <- intersections_of_hex(hex_id)
    expect_length(ints, 6L)
  }
})

test_that("hexes_at_intersection returns 1-3 hexes for every intersection", {
  for (int_id in 1:54) {
    hexes <- hexes_at_intersection(board, int_id)
    expect_true(length(hexes) >= 1 && length(hexes) <= 3,
                label = paste("intersection", int_id))
  }
})

test_that("adjacent_intersections returns non-empty results for all 54 intersections", {
  for (int_id in 1:54) {
    nbrs <- adjacent_intersections(int_id)
    expect_true(length(nbrs) >= 2,
                label = paste("intersection", int_id, "has at least 2 neighbours"))
  }
})

test_that("adjacency is symmetric: if j is adjacent to i, i is adjacent to j", {
  for (i in 1:54) {
    for (j in adjacent_intersections(i)) {
      expect_true(i %in% adjacent_intersections(j),
                  label = paste("symmetry between", i, "and", j))
    }
  }
})

test_that("get_edge returns an edge for two intersections that share a hex", {
  # Hex 1 uses intersections c(1,5,9,13,8,4) — consecutive pairs share edges
  # Intersection 1 is adjacent to 5 and 4
  e <- get_edge(board, 1L, 5L)
  expect_false(is.null(e))
  expect_true(setequal(e$ends, c(1L, 5L)))
})

test_that("get_edge returns NULL for intersections on opposite sides of the board", {
  # Intersections 1 and 54 are far apart and not directly connected
  e <- get_edge(board, 1L, 54L)
  expect_null(e)
})

# =============================================================================
# Placement validation
# =============================================================================

test_that("all intersections are valid settlement spots on a fresh board", {
  for (int_id in 1:54) {
    expect_true(is_valid_settlement_spot(board, int_id),
                label = paste("intersection", int_id, "valid on fresh board"))
  }
})

test_that("adjacent intersections become invalid after placing a settlement", {
  b <- place_structure(board, 10L, 1L, "settlement")
  # The placed spot itself is now occupied
  expect_false(is_valid_settlement_spot(b, 10L))
  # All neighbours of 10 must now also be invalid
  for (nbr in adjacent_intersections(10L)) {
    expect_false(is_valid_settlement_spot(b, nbr),
                 label = paste("neighbour", nbr, "invalid after settling at 10"))
  }
})

test_that("non-adjacent intersections stay valid after placing a settlement", {
  b <- place_structure(board, 1L, 1L, "settlement")
  # Intersection 54 is far from 1; it should still be valid
  expect_true(is_valid_settlement_spot(b, 54L))
})

# =============================================================================
# Board mutations
# =============================================================================

test_that("place_structure sets owner and structure correctly", {
  b <- place_structure(board, 5L, 2L, "settlement")
  expect_equal(b$intersections[[5L]]$owner,     2L)
  expect_equal(b$intersections[[5L]]$structure, "settlement")
})

test_that("place_structure can upgrade a settlement to a city", {
  b <- place_structure(board, 5L, 2L, "settlement")
  b <- place_structure(b,     5L, 2L, "city")
  expect_equal(b$intersections[[5L]]$structure, "city")
})

test_that("place_road sets the edge owner correctly", {
  b    <- place_road(board, 1L, 3L)
  expect_equal(b$edges[[1L]]$owner, 3L)
})

test_that("move_robber updates robber_hex and has_robber flags correctly", {
  desert_id  <- board$robber_hex
  target_id  <- if (desert_id == 1L) 2L else 1L
  b          <- move_robber(board, target_id)
  expect_equal(b$robber_hex, target_id)
  expect_true(b$hexes[[target_id]]$has_robber)
  expect_false(b$hexes[[desert_id]]$has_robber)
})

# =============================================================================
# Resource production
# =============================================================================

test_that("compute_production returns a data.frame with correct columns", {
  prod <- compute_production(board, 6L)
  expect_s3_class(prod, "data.frame")
  expect_named(prod, c("player_id", "resource", "amount"), ignore.order = TRUE)
})

test_that("compute_production returns empty data.frame on fresh board (no settlements)", {
  prod <- compute_production(board, 6L)
  expect_equal(nrow(prod), 0L)
})

test_that("compute_production yields 1 resource per settlement on matching hex", {
  # Place a settlement at the first intersection of hex 1, then roll hex 1's token
  target_hex <- board$hexes[[1L]]
  if (!is.na(target_hex$token)) {
    int_id <- intersections_of_hex(1L)[1]
    b      <- place_structure(board, int_id, 1L, "settlement")
    prod   <- compute_production(b, target_hex$token)
    row    <- prod[prod$player_id == 1L, ]
    expect_equal(nrow(row), 1L)
    expect_equal(row$amount, 1L)
    expect_equal(row$resource, target_hex$resource)
  } else {
    skip("hex 1 is the desert on this board — skipping production test")
  }
})

test_that("compute_production yields 2 resources per city on matching hex", {
  target_hex <- board$hexes[[1L]]
  if (!is.na(target_hex$token)) {
    int_id <- intersections_of_hex(1L)[1]
    b      <- place_structure(board, int_id, 1L, "city")
    prod   <- compute_production(b, target_hex$token)
    row    <- prod[prod$player_id == 1L, ]
    expect_equal(row$amount, 2L)
  } else {
    skip("hex 1 is the desert on this board")
  }
})

test_that("compute_production ignores hexes with the robber", {
  target_hex <- board$hexes[[1L]]
  if (!is.na(target_hex$token)) {
    int_id <- intersections_of_hex(1L)[1]
    b      <- place_structure(board, int_id, 1L, "settlement")
    b      <- move_robber(b, 1L)   # move robber onto hex 1
    prod   <- compute_production(b, target_hex$token)
    # Player 1 should not receive anything from hex 1
    p1_rows <- prod[!is.na(prod$player_id) & prod$player_id == 1L, ]
    expect_equal(nrow(p1_rows), 0L)
  } else {
    skip("hex 1 is the desert on this board")
  }
})

# =============================================================================
# get_edge_id
# =============================================================================

test_that("get_edge_id returns an integer ID for adjacent intersections", {
  eid <- get_edge_id(board, 1L, 5L)
  expect_false(is.na(eid))
  expect_type(eid, "integer")
  # The returned ID should point to an edge whose ends are {1, 5}
  expect_true(setequal(board$edges[[eid]]$ends, c(1L, 5L)))
})

test_that("get_edge_id returns NA for non-adjacent intersections", {
  eid <- get_edge_id(board, 1L, 54L)
  expect_true(is.na(eid))
})

# =============================================================================
# is_valid_road_spot
# =============================================================================

test_that("is_valid_road_spot returns FALSE on an occupied edge", {
  b    <- place_road(board, 1L, 2L)
  expect_false(is_valid_road_spot(b, 1L, 2L))
})

test_that("is_valid_road_spot returns TRUE when player has a settlement at one end", {
  # Place settlement at intersection 1, then check the edge from 1→5
  eid <- get_edge_id(board, 1L, 5L)
  b   <- place_structure(board, 1L, 1L, "settlement")
  expect_true(is_valid_road_spot(b, eid, 1L))
})

test_that("is_valid_road_spot returns FALSE when player has no connection", {
  eid <- get_edge_id(board, 1L, 5L)
  # Player 2 has no roads or settlements anywhere
  expect_false(is_valid_road_spot(board, eid, 2L))
})

test_that("is_valid_road_spot returns TRUE when connected via an existing road", {
  # Player 1 builds road 1→5, then should be able to extend to 5→9
  eid_15 <- get_edge_id(board, 1L, 5L)
  eid_59 <- get_edge_id(board, 5L, 9L)
  b <- place_road(board, eid_15, 1L)
  expect_true(is_valid_road_spot(b, eid_59, 1L))
})

# =============================================================================
# longest_road
# =============================================================================

test_that("longest_road returns 0 for a player with no roads", {
  expect_equal(longest_road(board, 1L), 0L)
})

test_that("longest_road returns 1 for a single road segment", {
  eid <- get_edge_id(board, 1L, 5L)
  b   <- place_road(board, eid, 1L)
  expect_equal(longest_road(b, 1L), 1L)
})

test_that("longest_road counts a simple chain correctly", {
  # Build a 3-segment chain: 4-1-5-9
  e1 <- get_edge_id(board, 4L, 1L)
  e2 <- get_edge_id(board, 1L, 5L)
  e3 <- get_edge_id(board, 5L, 9L)
  b  <- place_road(board, e1, 1L)
  b  <- place_road(b,     e2, 1L)
  b  <- place_road(b,     e3, 1L)
  expect_equal(longest_road(b, 1L), 3L)
})

test_that("longest_road is broken by an opponent's settlement", {
  # Chain 4-1-5-9, opponent at intersection 5
  e1 <- get_edge_id(board, 4L, 1L)
  e2 <- get_edge_id(board, 1L, 5L)
  e3 <- get_edge_id(board, 5L, 9L)
  b  <- place_road(board, e1, 1L)
  b  <- place_road(b,     e2, 1L)
  b  <- place_road(b,     e3, 1L)
  b  <- place_structure(b, 5L, 2L, "settlement")  # opponent blocks at 5
  # Longest unbroken segment is now 2 (4-1 and 1-5, or 5-9 alone = 1)
  expect_equal(longest_road(b, 1L), 2L)
})

test_that("longest_road does not count opponent roads", {
  eid <- get_edge_id(board, 1L, 5L)
  b   <- place_road(board, eid, 2L)  # player 2 owns it
  expect_equal(longest_road(b, 1L), 0L)
})

# =============================================================================
# board_hex_summary
# =============================================================================

test_that("board_hex_summary returns a data.frame with 19 rows", {
  summary_df <- board_hex_summary(board)
  expect_s3_class(summary_df, "data.frame")
  expect_equal(nrow(summary_df), 19L)
})

test_that("board_hex_summary has correct columns", {
  summary_df <- board_hex_summary(board)
  expect_named(summary_df, c("id", "terrain", "resource", "token", "pips", "has_robber"),
               ignore.order = TRUE)
})

test_that("board_hex_summary desert row has resource 'none' and token 0", {
  summary_df <- board_hex_summary(board)
  desert_row <- summary_df[summary_df$terrain == "desert", ]
  expect_equal(nrow(desert_row), 1L)
  expect_equal(desert_row$resource, "none")
  expect_equal(desert_row$token, 0L)
})

# =============================================================================
# board_port_summary
# =============================================================================

test_that("board_port_summary returns a data.frame with 18 rows (9 ports × 2)", {
  summary_df <- board_port_summary(board)
  expect_s3_class(summary_df, "data.frame")
  expect_equal(nrow(summary_df), 18L)
})

test_that("board_port_summary has correct columns", {
  summary_df <- board_port_summary(board)
  expect_named(summary_df, c("intersection_id", "resource", "rate"),
               ignore.order = TRUE)
})

test_that("board_port_summary rates are all 2 or 3", {
  summary_df <- board_port_summary(board)
  expect_true(all(summary_df$rate %in% c(2L, 3L)))
})

test_that("board_port_summary has 8 general and 10 specific port rows", {
  summary_df <- board_port_summary(board)
  expect_equal(sum(summary_df$resource == "general"), 8L)
  expect_equal(sum(summary_df$resource != "general"), 10L)
})

# =============================================================================
# best_port_for_player / trade_rate_for
# =============================================================================

test_that("best_port_for_player returns rate 4 when player has no ports", {
  player <- list(settlement_locations = integer(0))
  result <- best_port_for_player(board, player, "lumber")
  expect_equal(result$rate, 4L)
})

test_that("trade_rate_for returns 4 (bank rate) when player has no ports", {
  player <- list(settlement_locations = integer(0))
  expect_equal(trade_rate_for(board, player, "lumber"), 4L)
})

test_that("trade_rate_for returns 2 when player sits on a matching 2:1 port", {
  # Find a specific 2:1 port intersection and its resource
  port_ints    <- Filter(function(i) !is.null(i$port) && !is.na(i$port$resource),
                         board$intersections)
  target_int   <- port_ints[[1]]
  target_res   <- target_int$port$resource
  player       <- list(settlement_locations = target_int$id)
  expect_equal(trade_rate_for(board, player, target_res), 2L)
})

test_that("trade_rate_for returns 3 when player sits on a 3:1 general port", {
  general_ints <- Filter(function(i) !is.null(i$port) && is.na(i$port$resource),
                         board$intersections)
  target_int   <- general_ints[[1]]
  player       <- list(settlement_locations = target_int$id)
  # For a resource not covered by a specific 2:1 port, rate should be 3
  expect_equal(trade_rate_for(board, player, "ore"), 3L)
})

# =============================================================================
# Port randomness
# =============================================================================

test_that("fixed ports (random_ports = FALSE) are deterministic without a seed", {
  b1 <- generate_board(random_ports = FALSE)
  b2 <- generate_board(random_ports = FALSE)
  ports_1 <- vapply(b1$intersections,
                    function(i) if (is.null(i$port)) "none" else
                      paste(i$port$rate, ifelse(is.na(i$port$resource), "general",
                                                i$port$resource)),
                    character(1))
  ports_2 <- vapply(b2$intersections,
                    function(i) if (is.null(i$port)) "none" else
                      paste(i$port$rate, ifelse(is.na(i$port$resource), "general",
                                                i$port$resource)),
                    character(1))
  expect_equal(ports_1, ports_2)
})

# =============================================================================
# rolling 7 is not handled by compute_production (called separately)
# =============================================================================

test_that("rolling 7 is not handled by compute_production (called separately)", {
  # generate_board guarantees no hex has token 7; a roll of 7 never produces
  tokens <- vapply(board$hexes, function(h) if (is.na(h$token)) -1L else h$token,
                   integer(1))
  expect_false(7L %in% tokens)
})

# =============================================================================
# HEX_SPIRAL_ORDER constant
# =============================================================================

test_that("HEX_SPIRAL_ORDER has exactly 19 elements", {
  expect_length(HEX_SPIRAL_ORDER, 19L)
})

test_that("HEX_SPIRAL_ORDER is a permutation of hex IDs 1-19", {
  expect_equal(sort(HEX_SPIRAL_ORDER), 1L:19L)
})

test_that("consecutive hex IDs in HEX_SPIRAL_ORDER are adjacent on the board", {
  for (k in seq_len(length(HEX_SPIRAL_ORDER) - 1L)) {
    h1 <- HEX_SPIRAL_ORDER[k]
    h2 <- HEX_SPIRAL_ORDER[k + 1L]
    expect_true(h2 %in% HEX_ADJACENCY[[h1]],
                label = paste("spiral step", k, ": hex", h1, "adjacent to hex", h2))
  }
})

# =============================================================================
# STANDARD_TOKEN_SEQUENCE constant
# =============================================================================

test_that("STANDARD_TOKEN_SEQUENCE has exactly 18 elements", {
  expect_length(STANDARD_TOKEN_SEQUENCE, 18L)
})

test_that("STANDARD_TOKEN_SEQUENCE is a permutation of NUMBER_TOKENS", {
  expect_equal(sort(STANDARD_TOKEN_SEQUENCE), sort(NUMBER_TOKENS))
})

test_that("STANDARD_TOKEN_SEQUENCE contains no 7s", {
  expect_false(7L %in% STANDARD_TOKEN_SEQUENCE)
})

# =============================================================================
# HEX_ADJACENCY
# =============================================================================

test_that("HEX_ADJACENCY has 19 elements", {
  expect_length(HEX_ADJACENCY, 19L)
})

test_that("HEX_ADJACENCY is symmetric", {
  for (h1 in seq_len(19)) {
    for (h2 in HEX_ADJACENCY[[h1]]) {
      expect_true(h1 %in% HEX_ADJACENCY[[h2]],
                  label = paste("symmetry between hex", h1, "and hex", h2))
    }
  }
})

test_that("each hex has between 2 and 6 neighbours in HEX_ADJACENCY", {
  for (h in seq_len(19)) {
    n <- length(HEX_ADJACENCY[[h]])
    expect_true(n >= 2L && n <= 6L,
                label = paste("hex", h, "has", n, "neighbours"))
  }
})

test_that("known adjacent hex pairs appear in HEX_ADJACENCY", {
  # Hex 1 and hex 2 share intersections 5 and 9
  expect_true(2L %in% HEX_ADJACENCY[[1L]])
  # Hex 1 and hex 4 share intersections 8 and 13
  expect_true(4L %in% HEX_ADJACENCY[[1L]])
  # Centre hex 10 is surrounded by 6 neighbours
  expect_length(HEX_ADJACENCY[[10L]], 6L)
})

test_that("known non-adjacent hex pairs are absent from HEX_ADJACENCY", {
  # Hex 1 (top-left corner) and hex 19 (bottom-right corner) are far apart
  expect_false(19L %in% HEX_ADJACENCY[[1L]])
  # Hex 1 and hex 3 are in the same row but not neighbours (one hex gap)
  expect_false(3L %in% HEX_ADJACENCY[[1L]])
})

# =============================================================================
# Spiral token placement (random_tokens = FALSE)
# =============================================================================

test_that("spiral placement assigns tokens in STANDARD_TOKEN_SEQUENCE order", {
  # With fixed terrain the desert ends up at hex 19 (spiral position 7).
  # Walk the spiral manually and verify every non-desert hex gets the correct
  # token from STANDARD_TOKEN_SEQUENCE.
  b        <- generate_board(random_terrain = FALSE, random_tokens = FALSE)
  terrains <- vapply(b$hexes, `[[`, character(1), "terrain")
  desert_id <- which(terrains == "desert")

  token_iter <- 1L
  for (hex_id in HEX_SPIRAL_ORDER) {
    if (hex_id == desert_id) next
    expect_equal(b$hexes[[hex_id]]$token, STANDARD_TOKEN_SEQUENCE[token_iter],
                 label = paste("hex", hex_id, "(sequence pos", token_iter, ")"))
    token_iter <- token_iter + 1L
  }
})

test_that("spiral placement skips the desert correctly regardless of its position", {
  # Verify the spiral-skip logic across several seeds with random terrain.
  for (seed in c(1L, 7L, 42L, 99L)) {
    b         <- generate_board(random_terrain = TRUE, random_tokens = FALSE, seed = seed)
    terrains  <- vapply(b$hexes, `[[`, character(1), "terrain")
    desert_id <- which(terrains == "desert")

    token_iter <- 1L
    for (hex_id in HEX_SPIRAL_ORDER) {
      if (hex_id == desert_id) next
      expect_equal(b$hexes[[hex_id]]$token, STANDARD_TOKEN_SEQUENCE[token_iter],
                   label = paste("seed", seed, "hex", hex_id))
      token_iter <- token_iter + 1L
    }
  }
})

test_that("spiral placement assigns all 18 tokens (no hex missed)", {
  b          <- generate_board(random_terrain = FALSE, random_tokens = FALSE)
  non_desert <- Filter(function(h) h$terrain != "desert", b$hexes)
  tokens     <- sort(vapply(non_desert, `[[`, integer(1), "token"))
  expect_equal(tokens, sort(STANDARD_TOKEN_SEQUENCE))
})

# =============================================================================
# No adjacent red numbers (random_tokens = TRUE)
# =============================================================================

test_that("no two red tokens (6 or 8) are adjacent on a randomly generated board", {
  b         <- generate_board(seed = 42)
  tokens    <- vapply(b$hexes, function(h) if (is.na(h$token)) 0L else h$token, integer(1))
  red_hexes <- which(tokens %in% c(6L, 8L))
  for (rh in red_hexes) {
    neighbour_tokens <- tokens[HEX_ADJACENCY[[rh]]]
    expect_false(any(neighbour_tokens %in% c(6L, 8L)),
                 label = paste("red token at hex", rh, "has no adjacent red neighbour"))
  }
})

test_that("no adjacent red tokens across 20 randomly seeded boards", {
  for (seed in seq_len(20L)) {
    b         <- generate_board(seed = seed)
    tokens    <- vapply(b$hexes, function(h) if (is.na(h$token)) 0L else h$token, integer(1))
    red_hexes <- which(tokens %in% c(6L, 8L))
    for (rh in red_hexes) {
      neighbour_tokens <- tokens[HEX_ADJACENCY[[rh]]]
      expect_false(any(neighbour_tokens %in% c(6L, 8L)),
                   label = paste("seed", seed, "hex", rh))
    }
  }
})
