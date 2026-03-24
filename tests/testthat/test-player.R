source(file.path(dirname(dirname(getwd())), "R", "board.R"))
source(file.path(dirname(dirname(getwd())), "R", "player.R"))

# =============================================================================
# Helpers
# =============================================================================

# Create a fresh player and give them specific resources in one step.
player_with <- function(lumber = 0, brick = 0, wool = 0, grain = 0, ore = 0) {
  p <- make_player(id = 1L)
  p$resources <- c(lumber = as.integer(lumber),
                   brick  = as.integer(brick),
                   wool   = as.integer(wool),
                   grain  = as.integer(grain),
                   ore    = as.integer(ore))
  p
}

# =============================================================================
# make_player — constructor
# =============================================================================

test_that("make_player returns a list with all required fields", {
  p <- make_player(id = 1L)
  required <- c("id", "strategy_name", "resources", "dev_cards", "dev_cards_new",
                "dev_cards_played_this_turn", "knights_played",
                "road_locations", "settlement_locations", "city_locations",
                "has_longest_road", "has_largest_army", "vp")
  expect_named(p, required, ignore.order = TRUE)
})

test_that("new player starts with zero resources", {
  p <- make_player(id = 1L)
  expect_equal(sum(p$resources), 0L)
})

test_that("new player resource vector has exactly the five resource names", {
  p <- make_player(id = 1L)
  expect_named(p$resources, c("lumber", "brick", "wool", "grain", "ore"))
})

test_that("new player dev_cards vector has correct names", {
  p <- make_player(id = 1L)
  expected_names <- c("knight", "road_building", "year_of_plenty",
                      "monopoly", "victory_point")
  expect_named(p$dev_cards,     expected_names)
  expect_named(p$dev_cards_new, expected_names)
})

test_that("new player starts with zero dev cards", {
  p <- make_player(id = 1L)
  expect_equal(sum(p$dev_cards),     0L)
  expect_equal(sum(p$dev_cards_new), 0L)
})

test_that("new player starts with empty piece location vectors", {
  p <- make_player(id = 1L)
  expect_length(p$road_locations,       0L)
  expect_length(p$settlement_locations, 0L)
  expect_length(p$city_locations,       0L)
})

test_that("new player starts with 0 VP and no special cards", {
  p <- make_player(id = 1L)
  expect_equal(p$vp, 0L)
  expect_false(p$has_longest_road)
  expect_false(p$has_largest_army)
})

test_that("strategy_name is stored correctly", {
  p <- make_player(id = 2L, strategy_name = "sheep_strategy")
  expect_equal(p$strategy_name, "sheep_strategy")
})

test_that("make_player default strategy_name is 'unknown'", {
  p <- make_player(id = 1L)
  expect_equal(p$strategy_name, "unknown")
})


# =============================================================================
# Resource helpers — add / remove / count
# =============================================================================

test_that("add_resource increases the correct resource by the given amount", {
  p <- make_player(id = 1L)
  p <- add_resource(p, "wool", 3L)
  expect_equal(p$resources[["wool"]], 3L)
  # Other resources unaffected.
  expect_equal(p$resources[["ore"]], 0L)
})

test_that("add_resource is additive across multiple calls", {
  p <- make_player(id = 1L)
  p <- add_resource(p, "grain", 2L)
  p <- add_resource(p, "grain", 3L)
  expect_equal(p$resources[["grain"]], 5L)
})

test_that("add_resources adds all named amounts at once", {
  p <- make_player(id = 1L)
  p <- add_resources(p, c(lumber = 1L, ore = 2L))
  expect_equal(p$resources[["lumber"]], 1L)
  expect_equal(p$resources[["ore"]],    2L)
  expect_equal(p$resources[["wool"]],   0L)
})

test_that("remove_resource decreases the correct resource", {
  p <- player_with(wool = 4L)
  p <- remove_resource(p, "wool", 2L)
  expect_equal(p$resources[["wool"]], 2L)
})

test_that("remove_resources deducts multiple resources at once", {
  p <- player_with(lumber = 3L, brick = 2L)
  p <- remove_resources(p, c(lumber = 1L, brick = 2L))
  expect_equal(p$resources[["lumber"]], 2L)
  expect_equal(p$resources[["brick"]],  0L)
})

test_that("count_resources returns the sum of all resource cards", {
  p <- player_with(lumber = 1L, brick = 2L, wool = 3L)
  expect_equal(count_resources(p), 6L)
})

test_that("count_resources returns 0 for an empty hand", {
  p <- make_player(id = 1L)
  expect_equal(count_resources(p), 0L)
})

test_that("can_afford returns TRUE when player has exactly the required cards", {
  p <- player_with(lumber = 1L, brick = 1L)
  expect_true(can_afford(p, BUILD_COSTS[["road"]]))
})

test_that("can_afford returns FALSE when one resource is short by 1", {
  p <- player_with(lumber = 1L, brick = 0L)
  expect_false(can_afford(p, BUILD_COSTS[["road"]]))
})

test_that("can_afford returns TRUE for costs with zero requirements", {
  # A player with only grain+ore can afford a city (no lumber/brick needed).
  p <- player_with(grain = 2L, ore = 3L)
  expect_true(can_afford(p, BUILD_COSTS[["city"]]))
})


# =============================================================================
# can_build — resource + piece-limit validation
# =============================================================================

test_that("can_build road returns TRUE with enough resources and pieces", {
  p <- player_with(lumber = 1L, brick = 1L)
  expect_true(can_build(p, "road"))
})

test_that("can_build road returns FALSE when resources are missing", {
  p <- player_with(lumber = 1L, brick = 0L)
  expect_false(can_build(p, "road"))
})

test_that("can_build road returns FALSE at the 15-road piece limit", {
  p <- player_with(lumber = 1L, brick = 1L)
  p$road_locations <- 1L:15L   # simulate all 15 roads placed
  expect_false(can_build(p, "road"))
})

test_that("can_build settlement returns TRUE with enough resources and pieces", {
  # Settlement costs: 1 lumber, 1 brick, 1 wool, 1 grain.
  p <- player_with(lumber = 1L, brick = 1L, wool = 1L, grain = 1L)
  expect_true(can_build(p, "settlement"))
})

test_that("can_build settlement returns FALSE when ore is substituted for grain", {
  # Ore cannot substitute for grain — common beginner mistake.
  p <- player_with(lumber = 1L, brick = 1L, wool = 1L, ore = 1L)
  expect_false(can_build(p, "settlement"))
})

test_that("can_build settlement returns FALSE at the 5-settlement piece limit", {
  p <- player_with(lumber = 1L, brick = 1L, wool = 1L, grain = 1L)
  p$settlement_locations <- 1L:5L   # all 5 settlements placed
  expect_false(can_build(p, "settlement"))
})

test_that("can_build city returns TRUE with enough resources and an existing settlement", {
  # City costs: 3 ore, 2 grain.
  p <- player_with(ore = 3L, grain = 2L)
  p$settlement_locations <- 10L   # one settlement to upgrade
  expect_true(can_build(p, "city"))
})

test_that("can_build city returns FALSE when no settlements exist to upgrade", {
  # Even with full resources, a city must replace a settlement.
  p <- player_with(ore = 3L, grain = 2L)
  expect_false(can_build(p, "city"))
})

test_that("can_build city returns FALSE at the 4-city piece limit", {
  p <- player_with(ore = 3L, grain = 2L)
  p$settlement_locations <- 20L    # one settlement available
  p$city_locations       <- 1L:4L  # all 4 city pieces already placed
  expect_false(can_build(p, "city"))
})

test_that("can_build dev_card returns TRUE with 1 ore, 1 wool, 1 grain", {
  p <- player_with(ore = 1L, wool = 1L, grain = 1L)
  expect_true(can_build(p, "dev_card"))
})

test_that("can_build dev_card returns FALSE without ore", {
  p <- player_with(wool = 1L, grain = 1L)
  expect_false(can_build(p, "dev_card"))
})


# =============================================================================
# do_build — resource deduction
# =============================================================================

test_that("do_build road deducts exactly 1 lumber and 1 brick", {
  p <- player_with(lumber = 3L, brick = 2L)
  p <- do_build(p, "road")
  expect_equal(p$resources[["lumber"]], 2L)
  expect_equal(p$resources[["brick"]],  1L)
  expect_equal(p$resources[["wool"]],   0L)
})

test_that("do_build settlement deducts 1 each of lumber brick wool grain", {
  p <- player_with(lumber = 2L, brick = 2L, wool = 2L, grain = 2L)
  p <- do_build(p, "settlement")
  expect_equal(p$resources[["lumber"]], 1L)
  expect_equal(p$resources[["brick"]],  1L)
  expect_equal(p$resources[["wool"]],   1L)
  expect_equal(p$resources[["grain"]],  1L)
})

test_that("do_build city deducts 3 ore and 2 grain", {
  p <- player_with(ore = 4L, grain = 3L)
  p <- do_build(p, "city")
  expect_equal(p$resources[["ore"]],   1L)
  expect_equal(p$resources[["grain"]], 1L)
})

test_that("do_build dev_card deducts 1 ore, 1 wool, 1 grain", {
  p <- player_with(ore = 2L, wool = 2L, grain = 2L)
  p <- do_build(p, "dev_card")
  expect_equal(p$resources[["ore"]],   1L)
  expect_equal(p$resources[["wool"]],  1L)
  expect_equal(p$resources[["grain"]], 1L)
})


# =============================================================================
# Piece placement helpers — location recording and VP
# =============================================================================

test_that("add_road_location appends the edge ID", {
  p <- make_player(id = 1L)
  p <- add_road_location(p, 7L)
  expect_equal(p$road_locations, 7L)
  p <- add_road_location(p, 15L)
  expect_equal(p$road_locations, c(7L, 15L))
})

test_that("add_settlement_location appends intersection ID and adds 1 VP", {
  p <- make_player(id = 1L)
  p <- add_settlement_location(p, 10L)
  expect_equal(p$settlement_locations, 10L)
  expect_equal(p$vp, 1L)
})

test_that("placing two settlements gives 2 VP total", {
  p <- make_player(id = 1L)
  p <- add_settlement_location(p, 10L)
  p <- add_settlement_location(p, 20L)
  expect_equal(p$vp, 2L)
  expect_length(p$settlement_locations, 2L)
})

test_that("upgrade_to_city moves ID from settlements to cities and adds 1 VP net", {
  p <- make_player(id = 1L)
  p <- add_settlement_location(p, 10L)     # vp = 1
  p <- upgrade_to_city(p, 10L)             # vp = 2 (net +1)

  expect_length(p$settlement_locations, 0L)
  expect_equal(p$city_locations, 10L)
  expect_equal(p$vp, 2L)   # 1 (settlement) + 1 (city upgrade net gain)
})

test_that("upgrade_to_city leaves other settlements untouched", {
  p <- make_player(id = 1L)
  p <- add_settlement_location(p, 10L)
  p <- add_settlement_location(p, 20L)
  p <- upgrade_to_city(p, 10L)

  expect_equal(p$settlement_locations, 20L)
  expect_equal(p$city_locations, 10L)
  # 2 settlements placed (2 VP) + 1 city upgrade net gain (1 VP) = 3 VP total
  expect_equal(p$vp, 3L)
})


# =============================================================================
# Trading — bank and port
# =============================================================================

test_that("can_trade returns TRUE when player has enough of the give resource", {
  p <- player_with(wool = 4L)
  expect_true(can_trade(p, "wool", 4L))   # bank rate
})

test_that("can_trade returns FALSE when player is one short", {
  p <- player_with(wool = 3L)
  expect_false(can_trade(p, "wool", 4L))
})

test_that("can_trade returns TRUE with a 2:1 port and 2 matching cards", {
  p <- player_with(wool = 2L)
  expect_true(can_trade(p, "wool", 2L))   # 2:1 wool port rate
})

test_that("do_trade at bank rate (4:1) deducts 4 and adds 1 of different resource", {
  p <- player_with(wool = 5L)
  p <- do_trade(p, "wool", 4L, "ore")
  expect_equal(p$resources[["wool"]], 1L)
  expect_equal(p$resources[["ore"]],  1L)
})

test_that("do_trade at 3:1 port rate deducts 3 and adds 1", {
  p <- player_with(lumber = 3L)
  p <- do_trade(p, "lumber", 3L, "grain")
  expect_equal(p$resources[["lumber"]], 0L)
  expect_equal(p$resources[["grain"]],  1L)
})

test_that("do_trade at 2:1 port rate deducts 2 and adds 1", {
  p <- player_with(ore = 2L)
  p <- do_trade(p, "ore", 2L, "brick")
  expect_equal(p$resources[["ore"]],   0L)
  expect_equal(p$resources[["brick"]], 1L)
})

test_that("do_trade can trade into the same resource type (bank repurchase)", {
  # Unusual but not illegal: trade 4 wool for 1 wool reduces hand by 3.
  p <- player_with(wool = 4L)
  p <- do_trade(p, "wool", 4L, "wool")
  expect_equal(p$resources[["wool"]], 1L)
})


# =============================================================================
# Robber and discard mechanics
# =============================================================================

test_that("must_discard returns FALSE for exactly 7 cards", {
  p <- player_with(wool = 7L)
  expect_false(must_discard(p))
})

test_that("must_discard returns TRUE for 8 cards", {
  p <- player_with(wool = 8L)
  expect_true(must_discard(p))
})

test_that("discard_count returns 0 when hand <= 7", {
  p <- player_with(lumber = 3L, brick = 2L)
  expect_equal(discard_count(p), 0L)
})

test_that("discard_count returns floor(n/2) for 8 cards", {
  p <- player_with(wool = 8L)
  expect_equal(discard_count(p), 4L)   # floor(8/2) = 4
})

test_that("discard_count returns floor(n/2) for 13 cards (rounds down)", {
  p <- player_with(lumber = 5L, wool = 5L, ore = 3L)
  expect_equal(discard_count(p), 6L)   # floor(13/2) = 6
})

test_that("discard_to_limit leaves player with at most 7 cards when starting with 8", {
  p <- player_with(wool = 8L)
  p <- discard_to_limit(p)
  expect_equal(count_resources(p), 4L)   # 8 - floor(8/2) = 4
})

test_that("discard_to_limit is a no-op when hand is exactly 7", {
  p <- player_with(lumber = 3L, brick = 2L, grain = 2L)
  before <- p$resources
  p <- discard_to_limit(p)
  expect_equal(p$resources, before)
})

test_that("discard_to_limit removes the correct number of cards for odd hand sizes", {
  # 13 cards → discard floor(13/2) = 6, leaving 7
  p <- player_with(lumber = 5L, wool = 5L, ore = 3L)
  p <- discard_to_limit(p)
  expect_equal(count_resources(p), 7L)
})

test_that("discard_to_limit never produces negative resource counts", {
  p <- player_with(wool = 10L, lumber = 2L)
  p <- discard_to_limit(p)
  expect_true(all(p$resources >= 0L))
})

test_that("steal_resource transfers one card from victim to thief", {
  thief  <- make_player(id = 1L)
  victim <- player_with(ore = 3L)

  result <- steal_resource(thief, victim)

  expect_equal(count_resources(result$victim), 2L)
  expect_equal(count_resources(result$thief),  1L)
  # Total resources are conserved.
  expect_equal(
    count_resources(result$thief) + count_resources(result$victim),
    count_resources(victim)
  )
})

test_that("steal_resource transfers the specific resource type (single-type hand)", {
  thief  <- make_player(id = 1L)
  victim <- player_with(grain = 2L)

  result <- steal_resource(thief, victim)

  expect_equal(result$thief$resources[["grain"]], 1L)
  expect_equal(result$victim$resources[["grain"]], 1L)
})

test_that("steal_resource is a no-op when victim has no cards", {
  thief  <- make_player(id = 1L)
  victim <- make_player(id = 2L)   # empty hand

  result <- steal_resource(thief, victim)

  expect_equal(count_resources(result$thief),  0L)
  expect_equal(count_resources(result$victim), 0L)
})


# =============================================================================
# Development cards — draw, advance, play rules
# =============================================================================

test_that("draw_dev_card puts the card in dev_cards_new (not yet playable)", {
  p <- make_player(id = 1L)
  p <- draw_dev_card(p, "knight")

  expect_equal(p$dev_cards_new[["knight"]], 1L)
  expect_equal(p$dev_cards[["knight"]],     0L)  # not playable yet
})

test_that("advance_dev_cards moves new cards into playable hand", {
  p <- make_player(id = 1L)
  p <- draw_dev_card(p, "knight")
  p <- advance_dev_cards(p)

  expect_equal(p$dev_cards[["knight"]],     1L)
  expect_equal(p$dev_cards_new[["knight"]], 0L)
})

test_that("advance_dev_cards resets dev_cards_played_this_turn to FALSE", {
  p <- make_player(id = 1L)
  p$dev_cards[["knight"]]        <- 1L
  p$dev_cards_played_this_turn   <- TRUE

  p <- advance_dev_cards(p)

  expect_false(p$dev_cards_played_this_turn)
})

test_that("can_play_dev_card returns FALSE for a card not yet in playable hand", {
  p <- make_player(id = 1L)
  p <- draw_dev_card(p, "knight")   # in dev_cards_new only

  expect_false(can_play_dev_card(p, "knight"))
})

test_that("can_play_dev_card returns TRUE after advance_dev_cards", {
  p <- make_player(id = 1L)
  p <- draw_dev_card(p, "knight")
  p <- advance_dev_cards(p)

  expect_true(can_play_dev_card(p, "knight"))
})

test_that("can_play_dev_card returns FALSE when already played one card this turn", {
  p <- make_player(id = 1L)
  p$dev_cards[["knight"]]       <- 2L
  p$dev_cards_played_this_turn  <- TRUE

  expect_false(can_play_dev_card(p, "knight"))
})

test_that("VP dev cards cannot be actively played (they are passive reveals)", {
  p <- make_player(id = 1L)
  p$dev_cards[["victory_point"]] <- 3L

  expect_false(can_play_dev_card(p, "victory_point"))
})

test_that("spend_dev_card decrements the card count by 1", {
  p <- make_player(id = 1L)
  p$dev_cards[["road_building"]] <- 2L

  p <- spend_dev_card(p, "road_building")

  expect_equal(p$dev_cards[["road_building"]], 1L)
})

test_that("spend_dev_card sets dev_cards_played_this_turn to TRUE", {
  p <- make_player(id = 1L)
  p$dev_cards[["monopoly"]] <- 1L

  p <- spend_dev_card(p, "monopoly")

  expect_true(p$dev_cards_played_this_turn)
})

test_that("spending a knight increments knights_played", {
  p <- make_player(id = 1L)
  p$dev_cards[["knight"]] <- 3L

  p <- spend_dev_card(p, "knight")
  expect_equal(p$knights_played, 1L)

  p <- spend_dev_card(p, "knight")
  expect_equal(p$knights_played, 2L)
})

test_that("spending a non-knight card does not increment knights_played", {
  p <- make_player(id = 1L)
  p$dev_cards[["monopoly"]] <- 1L

  p <- spend_dev_card(p, "monopoly")
  expect_equal(p$knights_played, 0L)
})

# --- Year of Plenty ---

test_that("play_year_of_plenty adds two chosen resources to hand", {
  p <- make_player(id = 1L)
  p$dev_cards[["year_of_plenty"]] <- 1L

  p <- play_year_of_plenty(p, "ore", "grain")

  expect_equal(p$resources[["ore"]],   1L)
  expect_equal(p$resources[["grain"]], 1L)
})

test_that("play_year_of_plenty removes the card from hand", {
  p <- make_player(id = 1L)
  p$dev_cards[["year_of_plenty"]] <- 2L

  p <- play_year_of_plenty(p, "ore", "ore")

  expect_equal(p$dev_cards[["year_of_plenty"]], 1L)
})

test_that("play_year_of_plenty with two of the same resource adds 2 of that resource", {
  p <- make_player(id = 1L)
  p$dev_cards[["year_of_plenty"]] <- 1L

  p <- play_year_of_plenty(p, "ore", "ore")

  expect_equal(p$resources[["ore"]], 2L)
})

# --- Monopoly ---

test_that("play_monopoly transfers all targeted resource from opponents to player", {
  players <- list(
    make_player(id = 1L),
    player_with(wool = 3L),   # player 2 has 3 wool
    player_with(wool = 2L)    # player 3 has 2 wool
  )
  players[[1]]$dev_cards[["monopoly"]] <- 1L

  players <- play_monopoly(players, player_id = 1L, resource = "wool")

  expect_equal(players[[1]]$resources[["wool"]], 5L)   # 3 + 2 stolen
  expect_equal(players[[2]]$resources[["wool"]], 0L)
  expect_equal(players[[3]]$resources[["wool"]], 0L)
})

test_that("play_monopoly does not affect other resource types", {
  players <- list(
    make_player(id = 1L),
    player_with(wool = 2L, ore = 3L)
  )
  players[[1]]$dev_cards[["monopoly"]] <- 1L

  players <- play_monopoly(players, player_id = 1L, resource = "wool")

  # Ore should be untouched.
  expect_equal(players[[2]]$resources[["ore"]], 3L)
})

test_that("play_monopoly removes the monopoly card from hand", {
  players <- list(
    make_player(id = 1L),
    player_with(grain = 1L)
  )
  players[[1]]$dev_cards[["monopoly"]] <- 1L

  players <- play_monopoly(players, player_id = 1L, resource = "grain")

  expect_equal(players[[1]]$dev_cards[["monopoly"]], 0L)
})

test_that("play_monopoly on a resource nobody else has leaves hand unchanged", {
  players <- list(
    make_player(id = 1L),
    player_with(ore = 2L)
  )
  players[[1]]$dev_cards[["monopoly"]] <- 1L

  players <- play_monopoly(players, player_id = 1L, resource = "brick")

  expect_equal(players[[1]]$resources[["brick"]], 0L)
})

# --- Road Building ---

test_that("play_road_building removes the card from hand", {
  p <- make_player(id = 1L)
  p$dev_cards[["road_building"]] <- 2L

  p <- play_road_building(p)

  expect_equal(p$dev_cards[["road_building"]], 1L)
})

test_that("play_road_building sets dev_cards_played_this_turn", {
  p <- make_player(id = 1L)
  p$dev_cards[["road_building"]] <- 1L

  p <- play_road_building(p)

  expect_true(p$dev_cards_played_this_turn)
})

test_that("play_road_building does not change resource counts", {
  p <- player_with(lumber = 2L, brick = 2L)
  p$dev_cards[["road_building"]] <- 1L
  before <- p$resources

  p <- play_road_building(p)

  expect_equal(p$resources, before)
})


# =============================================================================
# Special card tracking — Longest Road and Largest Army
# =============================================================================

test_that("award_longest_road adds 2 VP and sets has_longest_road", {
  p <- make_player(id = 1L)
  p <- add_settlement_location(p, 1L)   # vp = 1
  p <- award_longest_road(p)

  expect_equal(p$vp, 3L)
  expect_true(p$has_longest_road)
})

test_that("award_longest_road is idempotent (calling twice does not double VP)", {
  p <- make_player(id = 1L)
  p <- award_longest_road(p)
  vp_after_first <- p$vp
  p <- award_longest_road(p)

  expect_equal(p$vp, vp_after_first)
})

test_that("revoke_longest_road removes 2 VP and clears has_longest_road", {
  p <- make_player(id = 1L)
  p <- award_longest_road(p)
  p <- revoke_longest_road(p)

  expect_equal(p$vp, 0L)
  expect_false(p$has_longest_road)
})

test_that("revoke_longest_road is a no-op when player does not hold the card", {
  p <- make_player(id = 1L)
  p$vp <- 3L
  p <- revoke_longest_road(p)   # should do nothing

  expect_equal(p$vp, 3L)
  expect_false(p$has_longest_road)
})

test_that("award_largest_army adds 2 VP and sets has_largest_army", {
  p <- make_player(id = 1L)
  p <- award_largest_army(p)

  expect_equal(p$vp, 2L)
  expect_true(p$has_largest_army)
})

test_that("award_largest_army is idempotent", {
  p <- make_player(id = 1L)
  p <- award_largest_army(p)
  vp_after_first <- p$vp
  p <- award_largest_army(p)

  expect_equal(p$vp, vp_after_first)
})

test_that("revoke_largest_army removes 2 VP and clears has_largest_army", {
  p <- make_player(id = 1L)
  p <- award_largest_army(p)
  p <- revoke_largest_army(p)

  expect_equal(p$vp, 0L)
  expect_false(p$has_largest_army)
})

test_that("revoke_largest_army is a no-op when player does not hold the card", {
  p <- make_player(id = 1L)
  p$vp <- 5L
  p <- revoke_largest_army(p)

  expect_equal(p$vp, 5L)
  expect_false(p$has_largest_army)
})

test_that("transferring Longest Road: old holder loses 2 VP, new holder gains 2 VP", {
  holder    <- make_player(id = 1L)
  contender <- make_player(id = 2L)

  holder    <- award_longest_road(holder)      # holder vp = 2
  holder    <- revoke_longest_road(holder)     # holder vp = 0
  contender <- award_longest_road(contender)   # contender vp = 2

  expect_equal(holder$vp,    0L)
  expect_false(holder$has_longest_road)
  expect_equal(contender$vp, 2L)
  expect_true(contender$has_longest_road)
})


# =============================================================================
# Victory point calculation
# =============================================================================

test_that("compute_vp returns visible VP when no VP dev cards held", {
  p <- make_player(id = 1L)
  p <- add_settlement_location(p, 1L)
  p <- add_settlement_location(p, 2L)

  expect_equal(compute_vp(p), 2L)
})

test_that("compute_vp includes VP dev cards in dev_cards (playable hand)", {
  p <- make_player(id = 1L)
  p <- add_settlement_location(p, 1L)         # visible vp = 1
  p$dev_cards[["victory_point"]] <- 2L        # hidden

  expect_equal(compute_vp(p), 3L)
})

test_that("compute_vp includes VP dev cards in dev_cards_new (drawn this turn)", {
  p <- make_player(id = 1L)
  p <- add_settlement_location(p, 1L)          # visible vp = 1
  p$dev_cards_new[["victory_point"]] <- 1L     # drawn this turn, still secret

  expect_equal(compute_vp(p), 2L)
})

test_that("has_won returns FALSE below 10 VP", {
  p <- make_player(id = 1L)
  # 2 settlements + 2 cities + largest army + longest road = 2+4+2+2 = 10,
  # so test with one fewer
  for (i in 1L:2L) p <- add_settlement_location(p, i)
  for (i in 3L:4L) {
    p <- add_settlement_location(p, i)
    p <- upgrade_to_city(p, i)
  }
  p <- award_largest_army(p)  # vp = 2+4+2 = 8
  p <- award_longest_road(p)  # vp = 10

  # Remove one road VP to stay below 10
  p <- revoke_longest_road(p)   # vp = 8

  expect_false(has_won(p))
})

test_that("has_won returns TRUE at exactly 10 VP", {
  p <- make_player(id = 1L)
  # Build to exactly 10 VP:
  # 5 settlements = 5 VP; upgrade 4 to cities = 5 + 4 = 9 VP visible; +1 VP card
  for (i in 1L:5L) p <- add_settlement_location(p, i)
  for (i in 1L:4L) p <- upgrade_to_city(p, i)             # vp = 1 + 4*2 = 9
  p$dev_cards[["victory_point"]] <- 1L                     # hidden +1 = 10 total
  expect_true(has_won(p))
})

test_that("has_won is TRUE even when the 10th VP comes from a hidden VP card", {
  p <- make_player(id = 1L)
  # 9 visible VP: 1 settlement + 4 cities + largest army + longest road
  for (i in 1L:5L) p <- add_settlement_location(p, i)
  for (i in 1L:4L) p <- upgrade_to_city(p, i)  # vp = 9
  # Hidden 10th point
  p$dev_cards_new[["victory_point"]] <- 1L

  expect_true(has_won(p))
})


# =============================================================================
# init_players and grant_initial_resources
# =============================================================================

test_that("init_players creates one player per strategy name", {
  players <- init_players(c("balanced", "sheep", "ore_grain"))
  expect_length(players, 3L)
})

test_that("init_players assigns sequential IDs starting from 1", {
  players <- init_players(c("balanced", "sheep"))
  expect_equal(players[[1]]$id, 1L)
  expect_equal(players[[2]]$id, 2L)
})

test_that("init_players stores the correct strategy names", {
  players <- init_players(c("balanced", "sheep"))
  expect_equal(players[[1]]$strategy_name, "balanced")
  expect_equal(players[[2]]$strategy_name, "sheep")
})

test_that("grant_initial_resources adds resources from adjacent non-desert hexes", {
  board <- generate_board(seed = 42)

  # Find an intersection adjacent to at least one non-desert hex.
  # Intersection 1 is in the top row and touches 1-2 hexes; pick one we can
  # inspect for its resources deterministically with seed 42.
  p <- make_player(id = 1L)
  int_id <- 24L   # interior intersection, guaranteed to touch 3 hexes

  hex_ids <- hexes_at_intersection(board, int_id)
  expected_res <- character(0)
  for (hid in hex_ids) {
    res <- board$hexes[[hid]]$resource
    if (!is.na(res)) expected_res <- c(expected_res, res)
  }

  p <- grant_initial_resources(p, board, int_id)

  # Total cards granted must equal number of non-desert adjacent hexes.
  expect_equal(count_resources(p), length(expected_res))
})

test_that("grant_initial_resources gives 0 resources if all adjacent hexes are desert", {
  # Build a minimal board where one hex is desert and covers intersection 1.
  # Easiest approach: place the second settlement directly on a desert-only
  # intersection by using a real board and finding a desert hex, then checking
  # that no resources are granted for its corners.
  board <- generate_board(seed = 42)
  desert_hex_id <- which(vapply(board$hexes, function(h) h$terrain == "desert",
                                logical(1)))
  desert_ints <- HEX_INTERSECTIONS[[desert_hex_id]]

  # Find any desert corner that is ONLY adjacent to the desert hex.
  only_desert <- vapply(desert_ints, function(int_id) {
    adj_hexes <- hexes_at_intersection(board, int_id)
    all(vapply(adj_hexes, function(hid) board$hexes[[hid]]$terrain == "desert",
               logical(1)))
  }, logical(1))

  if (any(only_desert)) {
    pure_desert_int <- desert_ints[which(only_desert)[1]]
    p <- make_player(id = 1L)
    p <- grant_initial_resources(p, board, pure_desert_int)
    expect_equal(count_resources(p), 0L)
  } else {
    skip("No intersection adjacent only to desert on this board layout")
  }
})


# =============================================================================
# player_summary
# =============================================================================

test_that("player_summary returns a single-row data.frame", {
  p <- make_player(id = 1L, strategy_name = "balanced")
  s <- player_summary(p)
  expect_s3_class(s, "data.frame")
  expect_equal(nrow(s), 1L)
})

test_that("player_summary includes all expected columns", {
  p <- make_player(id = 1L)
  s <- player_summary(p)
  expected_cols <- c("id", "strategy", "lumber", "brick", "wool", "grain", "ore",
                     "total_resources", "roads", "settlements", "cities",
                     "knights_in_hand", "knights_played", "vp_cards",
                     "vp_public", "vp_total", "has_longest_road", "has_largest_army")
  expect_named(s, expected_cols, ignore.order = TRUE)
})

test_that("player_summary vp_total matches compute_vp", {
  p <- make_player(id = 1L)
  p <- add_settlement_location(p, 1L)
  p$dev_cards[["victory_point"]] <- 2L

  s <- player_summary(p)
  expect_equal(s$vp_total, compute_vp(p))
})

test_that("player_summary correctly reports piece counts", {
  p <- make_player(id = 1L)
  p <- add_road_location(p, 5L)
  p <- add_road_location(p, 6L)
  p <- add_settlement_location(p, 10L)
  p <- add_settlement_location(p, 20L)
  p <- upgrade_to_city(p, 20L)

  s <- player_summary(p)
  expect_equal(s$roads,       2L)
  expect_equal(s$settlements, 1L)
  expect_equal(s$cities,      1L)
})


# =============================================================================
# Constants — sanity checks
# =============================================================================

test_that("BUILD_COSTS has entries for road, settlement, city, dev_card", {
  expect_true(all(c("road", "settlement", "city", "dev_card") %in% names(BUILD_COSTS)))
})

test_that("PIECE_LIMITS are 15 roads, 5 settlements, 4 cities", {
  expect_equal(PIECE_LIMITS[["road"]],       15L)
  expect_equal(PIECE_LIMITS[["settlement"]], 5L)
  expect_equal(PIECE_LIMITS[["city"]],       4L)
})

test_that("DEV_CARD_COUNTS sum to 25 (standard Catan deck)", {
  expect_equal(sum(DEV_CARD_COUNTS), 25L)
})

test_that("DEV_CARD_COUNTS contains 14 knights", {
  expect_equal(DEV_CARD_COUNTS[["knight"]], 14L)
})

test_that("DEV_CARD_COUNTS contains 5 VP cards", {
  expect_equal(DEV_CARD_COUNTS[["victory_point"]], 5L)
})

test_that("LARGEST_ARMY_MIN is 3", {
  expect_equal(LARGEST_ARMY_MIN, 3L)
})

test_that("LONGEST_ROAD_MIN is 5", {
  expect_equal(LONGEST_ROAD_MIN, 5L)
})
