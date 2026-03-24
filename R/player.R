# =============================================================================
# player.R
# Player state representation and resource/build management.
#
# Each player is a plain R named list. Functions in this module create and
# mutate player state: adding/removing resource cards, validating and executing
# builds, trading with the bank or a port, and managing development cards.
#
# Design principles (consistent with board.R):
#   - All mutation functions return a NEW player list rather than modifying in
#     place.  This keeps state management explicit and avoids R's copy-on-modify
#     surprises when the same list is referenced from multiple places.
#   - Functions are small and single-purpose so game.R and strategy.R can
#     compose them freely.
#   - No board.R functions are called here directly; any function that needs
#     board information (e.g. grant_initial_resources) receives the board as an
#     argument.
# =============================================================================


# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------

# Build costs: named integer vector for each purchasable item.
# Keys are the five resource names used throughout the simulation.
# A value of 0 means that resource is not required for the item.
BUILD_COSTS <- list(
  road       = c(lumber = 1L, brick = 1L, wool = 0L, grain = 0L, ore = 0L),
  settlement = c(lumber = 1L, brick = 1L, wool = 1L, grain = 1L, ore = 0L),
  city       = c(lumber = 0L, brick = 0L, wool = 0L, grain = 2L, ore = 3L),
  dev_card   = c(lumber = 0L, brick = 0L, wool = 1L, grain = 1L, ore = 1L)
)

# Hard physical piece limits per player (standard Catan rules).
# A player cannot build beyond these counts even with sufficient resources.
PIECE_LIMITS <- c(
  road       = 15L,
  settlement =  5L,
  city       =  4L
)

# Standard development card deck composition (25 cards total).
# The deck is managed externally by game.R; these counts are used here for
# reference and for initialising player dev-card hand vectors.
DEV_CARD_COUNTS <- c(
  knight         = 14L,  # move robber + steal; drives Largest Army
  road_building  =  2L,  # place 2 free roads immediately
  year_of_plenty =  2L,  # take any 2 resource cards from the bank
  monopoly       =  2L,  # claim all of one resource from every other player
  victory_point  =  5L   # +1 VP; kept secret until claiming victory
)

# Victory point values awarded by each source.
# Settlements and cities contribute directly to player$vp; special cards are
# tracked via the has_longest_road / has_largest_army flags (also reflected in
# player$vp); VP dev cards are hidden until victory and are counted only by
# compute_vp().
VP_VALUES <- c(
  settlement    = 1L,
  city          = 2L,   # net gain when upgrading: city(2) - settlement(1) = +1
  largest_army  = 2L,
  longest_road  = 2L,
  victory_point = 1L    # per VP dev card held
)

# Thresholds for claiming the two special cards.
LARGEST_ARMY_MIN <- 3L   # first to play 3+ knights claims Largest Army
LONGEST_ROAD_MIN <- 5L   # first to build a continuous road of 5+ segments


# =============================================================================
# Player constructor
# =============================================================================

#' Create a new player object with all fields initialised to starting values.
#'
#' Players begin with no resources, no structures, and an empty dev-card hand.
#' Initial settlement and road locations are added later by the game loop
#' calling add_settlement_location() and add_road_location().
#'
#' @param id             Integer player index (1 .. number_of_players).
#' @param strategy_name  Character label for which strategy this player uses.
#'                       Stored for result analysis; not used for gameplay.
#' @return A named list representing the player's complete state.
make_player <- function(id, strategy_name = "unknown") {
  list(
    # --- Identity ---
    id            = id,
    strategy_name = strategy_name,

    # --- Resource hand ---
    # Named integer vector; keys are the five resource names from board.R.
    # Starts at zero for all resources; incremented by add_resource() each turn.
    resources = c(lumber = 0L, brick = 0L, wool = 0L,
                  grain  = 0L, ore   = 0L),

    # --- Development cards (playable) ---
    # Cards in this vector can be played on the current or future turns.
    # Cards drawn during the current turn live in dev_cards_new until
    # advance_dev_cards() is called at the start of the player's NEXT turn.
    dev_cards = c(knight         = 0L,
                  road_building  = 0L,
                  year_of_plenty = 0L,
                  monopoly       = 0L,
                  victory_point  = 0L),

    # --- Development cards drawn this turn (not yet playable) ---
    # Merged into dev_cards at the start of the player's next turn.
    # Prevents the "draw and immediately play" exploit.
    dev_cards_new = c(knight         = 0L,
                      road_building  = 0L,
                      year_of_plenty = 0L,
                      monopoly       = 0L,
                      victory_point  = 0L),

    # Flag: has this player already played a non-VP dev card this turn?
    # Only one active dev card (knight / road building / year of plenty /
    # monopoly) may be played per turn.  Resets each turn via
    # advance_dev_cards().
    dev_cards_played_this_turn = FALSE,

    # --- Played knight counter ---
    # Tracks the cumulative knights played (not just this turn) for the
    # Largest Army calculation.
    knights_played = 0L,

    # --- Piece location tracking ---
    # Integer vectors appended as pieces are placed on the board.
    # road_locations:       edge IDs of placed roads
    # settlement_locations: intersection IDs with active settlements
    # city_locations:       intersection IDs with cities (upgraded settlements)
    road_locations       = integer(0),
    settlement_locations = integer(0),
    city_locations       = integer(0),

    # --- Special card flags ---
    # These mirror the VP entries in player$vp for explicit state checks.
    has_longest_road = FALSE,
    has_largest_army = FALSE,

    # --- Visible victory points ---
    # Tracks VP from structures (settlements, cities) and special cards
    # (Longest Road, Largest Army) only.  VP dev cards are HIDDEN and are
    # not included here; use compute_vp() to get the full true total.
    vp = 0L
  )
}


# =============================================================================
# Resource helpers
# =============================================================================

#' Add a quantity of one resource to a player's hand.
#'
#' The primary way resources enter a player's hand: dice-roll production,
#' Year of Plenty, and initial resource grants all route through here.
#'
#' @param player   Player list.
#' @param resource Character resource name; must be one of RESOURCES in board.R.
#' @param amount   Non-negative integer number of cards to add.
#' @return Updated player list.
add_resource <- function(player, resource, amount) {
  player$resources[[resource]] <- player$resources[[resource]] + as.integer(amount)
  player
}

#' Add multiple resources at once from a named integer vector.
#'
#' Convenience wrapper around add_resource() used when distributing production
#' results that may cover several resource types in one shot.
#'
#' @param player  Player list.
#' @param amounts Named integer vector; names must be valid resource names.
#'                Any names not present in player$resources are silently ignored.
#' @return Updated player list.
add_resources <- function(player, amounts) {
  for (res in names(amounts)) {
    player <- add_resource(player, res, amounts[[res]])
  }
  player
}

#' Remove a quantity of one resource from a player's hand.
#'
#' Used when paying build costs, discarding on a 7, or executing a trade.
#' Does NOT enforce non-negativity; callers should verify with can_afford()
#' or can_trade() first to avoid negative resource counts.
#'
#' @param player   Player list.
#' @param resource Character resource name.
#' @param amount   Non-negative integer number of cards to remove.
#' @return Updated player list.
remove_resource <- function(player, resource, amount) {
  player$resources[[resource]] <- player$resources[[resource]] - as.integer(amount)
  player
}

#' Remove multiple resources at once from a named integer vector.
#'
#' Mirrors add_resources() for bulk deductions (e.g. paying a build cost).
#'
#' @param player  Player list.
#' @param amounts Named integer vector of resources to deduct.
#' @return Updated player list.
remove_resources <- function(player, amounts) {
  for (res in names(amounts)) {
    player <- remove_resource(player, res, amounts[[res]])
  }
  player
}

#' Count the total number of resource cards held by a player.
#'
#' Used to check the 7-card discard threshold and for the robber-steal
#' probability (victim must have at least 1 card to steal from).
#'
#' @param player Player list.
#' @return Integer total card count across all resource types.
count_resources <- function(player) {
  sum(player$resources)
}

#' Check whether a player can afford a given cost vector.
#'
#' Compares each required resource against the player's hand.
#' Returns FALSE as soon as any single resource is insufficient.
#'
#' @param player Player list.
#' @param cost   Named integer vector of required resources.
#'               Typically one of the BUILD_COSTS entries.
#' @return TRUE if the player holds at least the required amount of each resource.
can_afford <- function(player, cost) {
  all(player$resources[names(cost)] >= cost)
}


# =============================================================================
# Build helpers
# =============================================================================

#' Check whether a player can legally initiate a build.
#'
#' Validates two independent conditions:
#'   1. The player has sufficient resources (via can_afford).
#'   2. The player has remaining pieces of that type (piece limits).
#'
#' Does NOT check board placement legality (intersection distance rule, road
#' connectivity, etc.) — that is handled by is_valid_settlement_spot() and
#' is_valid_road_spot() in board.R, called from game.R / strategy.R.
#'
#' For "city": also requires the player to have at least one settlement to
#' upgrade (you cannot build a city on an empty intersection).
#'
#' For "dev_card": the deck-size limit is enforced by game.R (deck object);
#' this function only checks resource affordability.
#'
#' @param player Player list.
#' @param item   Character; one of "road", "settlement", "city", "dev_card".
#' @return TRUE if the build is affordable and piece supply allows it.
can_build <- function(player, item) {
  # Check resources first — cheapest gate.
  if (!can_afford(player, BUILD_COSTS[[item]])) return(FALSE)

  if (item == "road") {
    # Must have at least one road piece remaining in supply.
    return(length(player$road_locations) < PIECE_LIMITS[["road"]])
  }

  if (item == "settlement") {
    # Must have at least one settlement piece remaining.
    return(length(player$settlement_locations) < PIECE_LIMITS[["settlement"]])
  }

  if (item == "city") {
    # Must have a city piece available AND an existing settlement to upgrade.
    return(
      length(player$city_locations)       < PIECE_LIMITS[["city"]] &&
      length(player$settlement_locations) > 0L
    )
  }

  # "dev_card": resource check already passed above; deck limit is external.
  TRUE
}

#' Deduct the resource cost of a build from the player's hand.
#'
#' This function handles ONLY the resource deduction.  Updating piece location
#' vectors (road_locations, settlement_locations, city_locations) is done
#' separately by add_road_location(), add_settlement_location(), or
#' upgrade_to_city() so that game.R can interleave placement validation cleanly.
#'
#' For free placements (Road Building card, initial setup), skip this call and
#' use the location-recording helpers directly.
#'
#' @param player Player list.
#' @param item   Character; one of "road", "settlement", "city", "dev_card".
#' @return Updated player list with resources deducted.
do_build <- function(player, item) {
  remove_resources(player, BUILD_COSTS[[item]])
}

#' Record that a road has been placed at a given edge ID.
#'
#' Separated from do_build() so that free roads (Road Building card, initial
#' setup) can also be recorded without touching resource counts.
#'
#' @param player  Player list.
#' @param edge_id Integer edge ID from board$edges.
#' @return Updated player list with the edge appended to road_locations.
add_road_location <- function(player, edge_id) {
  player$road_locations <- c(player$road_locations, as.integer(edge_id))
  player
}

#' Record that a settlement has been placed at a given intersection.
#'
#' Appends the intersection ID to settlement_locations and increments visible
#' VP by 1.  Called for both initial-placement settlements (no resource cost)
#' and normal-turn settlements (resources already deducted by do_build()).
#'
#' @param player          Player list.
#' @param intersection_id Integer intersection ID from board$intersections.
#' @return Updated player list.
add_settlement_location <- function(player, intersection_id) {
  player$settlement_locations <- c(player$settlement_locations,
                                   as.integer(intersection_id))
  player$vp <- player$vp + VP_VALUES[["settlement"]]
  player
}

#' Upgrade a settlement to a city at the given intersection.
#'
#' Moves the intersection ID from settlement_locations to city_locations and
#' increments visible VP by 1 (the net gain: city = 2 VP, settlement = 1 VP).
#'
#' The resource cost (3 ore + 2 grain) must already have been deducted by
#' do_build() before calling this function.
#'
#' @param player          Player list.
#' @param intersection_id Integer intersection ID to upgrade.
#' @return Updated player list.
upgrade_to_city <- function(player, intersection_id) {
  intersection_id <- as.integer(intersection_id)

  # Remove from active settlements.
  player$settlement_locations <- player$settlement_locations[
    player$settlement_locations != intersection_id
  ]

  # Add to city list.
  player$city_locations <- c(player$city_locations, intersection_id)

  # Net VP gain: city (2) - settlement (1) = +1.
  player$vp <- player$vp + (VP_VALUES[["city"]] - VP_VALUES[["settlement"]])

  player
}


# =============================================================================
# Trading (bank and ports)
# =============================================================================

#' Check whether a player can execute a specific bank or port trade.
#'
#' The player must hold at least give_count copies of give_resource.
#' The best available trade rate for the player is determined in board.R via
#' trade_rate_for(board, player, resource) and passed in here as give_count.
#'
#' @param player        Player list.
#' @param give_resource Character resource name to give.
#' @param give_count    Integer; how many of give_resource to spend (trade rate).
#' @return TRUE if the player holds at least give_count of give_resource.
can_trade <- function(player, give_resource, give_count) {
  player$resources[[give_resource]] >= as.integer(give_count)
}

#' Execute a bank or port trade.
#'
#' Deducts give_count of give_resource and adds 1 of receive_resource.
#' The caller (game.R / strategy.R) is responsible for determining the
#' applicable rate via trade_rate_for() from board.R and passing it here as
#' give_count.  Multiple trades can be chained by calling this function
#' repeatedly on the returned player.
#'
#' @param player           Player list.
#' @param give_resource    Character; resource being given to the bank/port.
#' @param give_count       Integer; trade rate (2, 3, or 4).
#' @param receive_resource Character; resource received in return.
#' @return Updated player list with the trade applied.
do_trade <- function(player, give_resource, give_count, receive_resource) {
  player <- remove_resource(player, give_resource, as.integer(give_count))
  player <- add_resource(player, receive_resource, 1L)
  player
}


# =============================================================================
# Robber and discard mechanics
# =============================================================================

#' Check whether a player must discard when a 7 is rolled.
#'
#' Standard Catan rule: any player holding strictly more than 7 resource cards
#' must discard exactly floor(n / 2) cards before the active player places
#' the robber.
#'
#' @param player Player list.
#' @return TRUE if the player's total resource count exceeds 7.
must_discard <- function(player) {
  count_resources(player) > 7L
}

#' Compute the number of cards a player must discard on a 7 roll.
#'
#' Returns floor(n / 2) where n is the total card count.
#' Returns 0L if the player does not need to discard (n <= 7).
#'
#' @param player Player list.
#' @return Integer number of cards to discard.
discard_count <- function(player) {
  n <- count_resources(player)
  if (n <= 7L) return(0L)
  as.integer(floor(n / 2L))
}

#' Discard down to the legal hand limit after a 7 is rolled.
#'
#' Uses a greedy approach: discard one card at a time from whichever resource
#' the player holds the most of.  This is a simple, reasonable default; a
#' strategy may override this with smarter logic (e.g. keep ore/grain for
#' cities) by modifying player$resources directly and calling this function
#' only as a fallback.
#'
#' The greedy approach ensures wool surplus — the hallmark of the sheep
#' strategy — is discarded first when wool is over-held, modelling its
#' real strategic weakness.
#'
#' @param player Player list.
#' @return Updated player list with excess cards removed.
discard_to_limit <- function(player) {
  n_discard <- discard_count(player)
  if (n_discard == 0L) return(player)

  for (i in seq_len(n_discard)) {
    # Identify the most-held resource and discard one copy.
    max_res <- names(which.max(player$resources))
    player  <- remove_resource(player, max_res, 1L)
  }

  player
}

#' Steal one random resource card from a victim player.
#'
#' Used when the active player moves the robber (roll of 7 or Knight card)
#' and chooses a victim with at least one settlement or city adjacent to the
#' new robber location.
#'
#' The stolen resource is chosen uniformly at random from the victim's hand,
#' simulating the physical action of drawing a face-down card.
#'
#' @param thief  Player list of the player doing the stealing.
#' @param victim Player list of the player being stolen from.
#' @return Named list with elements $thief and $victim, both updated.
steal_resource <- function(thief, victim) {
  # If the victim has no cards there is nothing to steal.
  if (count_resources(victim) == 0L) {
    return(list(thief = thief, victim = victim))
  }

  # Expand the hand into a flat character vector and pick one card at random.
  hand       <- rep(names(victim$resources), times = victim$resources)
  stolen_res <- sample(hand, 1L)

  victim <- remove_resource(victim, stolen_res, 1L)
  thief  <- add_resource(thief,  stolen_res, 1L)

  list(thief = thief, victim = victim)
}


# =============================================================================
# Development cards
# =============================================================================

#' Draw a development card from the deck into the player's new-card hand.
#'
#' Cards drawn this turn are stored in dev_cards_new and cannot be played until
#' the player's NEXT turn (standard Catan rule).  Call advance_dev_cards() at
#' the start of each subsequent turn to move them into the playable hand.
#'
#' The deck itself (shuffled character vector) is managed by game.R.  This
#' function only records that the player received a specific card type.
#'
#' @param player    Player list.
#' @param card_type Character; one of the names in DEV_CARD_COUNTS.
#' @return Updated player list with the card added to dev_cards_new.
draw_dev_card <- function(player, card_type) {
  player$dev_cards_new[[card_type]] <- player$dev_cards_new[[card_type]] + 1L
  player
}

#' Move newly drawn dev cards into the playable hand at the start of a turn.
#'
#' Call this at the BEGINNING of each player's turn, before any decisions.
#' Merges dev_cards_new into dev_cards (elementwise addition), resets
#' dev_cards_new to all-zero, and clears the one-card-per-turn flag.
#'
#' @param player Player list.
#' @return Updated player list ready for the new turn.
advance_dev_cards <- function(player) {
  player$dev_cards              <- player$dev_cards + player$dev_cards_new
  player$dev_cards_new          <- player$dev_cards_new * 0L  # zero all slots
  player$dev_cards_played_this_turn <- FALSE
  player
}

#' Check whether a player can play a specific dev card on their current turn.
#'
#' Returns FALSE if:
#'   - The player holds zero copies in their playable hand (dev_cards).
#'   - The card type is "victory_point" (VP cards are revealed passively, not
#'     played as an action).
#'   - The player has already played a non-VP dev card this turn.
#'
#' @param player    Player list.
#' @param card_type Character; one of the names in DEV_CARD_COUNTS.
#' @return TRUE if the card can be played right now.
can_play_dev_card <- function(player, card_type) {
  # Must hold at least one copy.
  if (player$dev_cards[[card_type]] < 1L) return(FALSE)
  # VP cards are not actively played; they are revealed when winning.
  if (card_type == "victory_point") return(FALSE)
  # Only one active dev card per turn.
  !player$dev_cards_played_this_turn
}

#' Remove a dev card from the playable hand and flag that one was played.
#'
#' Internal bookkeeping step shared by all "play_*" functions below.
#' Knight cards also increment knights_played for Largest Army tracking.
#' The actual game effect of the card (placing the robber, granting roads,
#' etc.) is applied in game.R / strategy.R after this call.
#'
#' @param player    Player list.
#' @param card_type Character; non-VP dev card type being played.
#' @return Updated player list.
spend_dev_card <- function(player, card_type) {
  player$dev_cards[[card_type]]      <- player$dev_cards[[card_type]] - 1L
  player$dev_cards_played_this_turn  <- TRUE

  # Knights fuel Largest Army — track them separately.
  if (card_type == "knight") {
    player$knights_played <- player$knights_played + 1L
  }

  player
}

#' Play a Year of Plenty card: receive any two resources from the bank.
#'
#' Spends the card (via spend_dev_card) and immediately grants res1 and res2
#' to the player.  The strategy chooses which two resources to take.
#'
#' @param player Player list.
#' @param res1   Character; first resource to receive.
#' @param res2   Character; second resource to receive (may be the same as res1).
#' @return Updated player list.
play_year_of_plenty <- function(player, res1, res2) {
  player <- spend_dev_card(player, "year_of_plenty")
  player <- add_resource(player, res1, 1L)
  player <- add_resource(player, res2, 1L)
  player
}

#' Play a Monopoly card: claim all of one resource from every other player.
#'
#' Iterates over all players, transfers every copy of the named resource from
#' each opponent to the monopoly player, and marks the card as spent.
#' Returns the FULL players list because multiple players are affected.
#'
#' @param players   List of all player objects, indexed by player ID.
#' @param player_id Integer index of the player playing Monopoly.
#' @param resource  Character; the resource to monopolise.
#' @return Updated players list (all opponents drained, monopoly player enriched).
play_monopoly <- function(players, player_id, resource) {
  # Spend the card before calculating the haul.
  players[[player_id]] <- spend_dev_card(players[[player_id]], "monopoly")

  total_stolen <- 0L
  for (i in seq_along(players)) {
    if (i == player_id) next  # cannot steal from yourself

    stolen <- players[[i]]$resources[[resource]]
    if (stolen > 0L) {
      players[[i]] <- remove_resource(players[[i]], resource, stolen)
      total_stolen  <- total_stolen + stolen
    }
  }

  # Grant everything stolen to the monopoly player at once.
  players[[player_id]] <- add_resource(players[[player_id]], resource, total_stolen)
  players
}

#' Play a Road Building card: mark the card as spent.
#'
#' Returns the updated player with the road_building card deducted and
#' dev_cards_played_this_turn set to TRUE.  The actual road placements
#' (two free roads at any valid locations) are handled in game.R / strategy.R
#' after this call using add_road_location() for each chosen edge.
#'
#' @param player Player list.
#' @return Updated player list with road_building card spent.
play_road_building <- function(player) {
  spend_dev_card(player, "road_building")
}


# =============================================================================
# Special card tracking (Longest Road & Largest Army)
# =============================================================================

#' Award the Longest Road special card to a player.
#'
#' Adds 2 VP and sets has_longest_road = TRUE.  No-ops if the player already
#' holds the card (prevents double-awarding on edge cases).
#' Callers (game.R) must call revoke_longest_road() on the previous holder
#' before calling this function.
#'
#' @param player Player list.
#' @return Updated player list.
award_longest_road <- function(player) {
  if (!player$has_longest_road) {
    player$has_longest_road <- TRUE
    player$vp               <- player$vp + VP_VALUES[["longest_road"]]
  }
  player
}

#' Revoke the Longest Road special card from its current holder.
#'
#' Deducts 2 VP and clears has_longest_road.  Called when another player
#' builds a longer road and claims the card.
#'
#' @param player Player list.
#' @return Updated player list.
revoke_longest_road <- function(player) {
  if (player$has_longest_road) {
    player$has_longest_road <- FALSE
    player$vp               <- player$vp - VP_VALUES[["longest_road"]]
  }
  player
}

#' Award the Largest Army special card to a player.
#'
#' Adds 2 VP and sets has_largest_army = TRUE.  Callers (game.R) must call
#' revoke_largest_army() on the previous holder first.
#'
#' @param player Player list.
#' @return Updated player list.
award_largest_army <- function(player) {
  if (!player$has_largest_army) {
    player$has_largest_army <- TRUE
    player$vp               <- player$vp + VP_VALUES[["largest_army"]]
  }
  player
}

#' Revoke the Largest Army special card from its current holder.
#'
#' Deducts 2 VP and clears has_largest_army.  Called when another player
#' surpasses the current holder's knight count.
#'
#' @param player Player list.
#' @return Updated player list.
revoke_largest_army <- function(player) {
  if (player$has_largest_army) {
    player$has_largest_army <- FALSE
    player$vp               <- player$vp - VP_VALUES[["largest_army"]]
  }
  player
}


# =============================================================================
# Victory point calculation
# =============================================================================

#' Compute a player's true total VP, including hidden VP dev cards.
#'
#' player$vp holds only the publicly visible VP (structures + special cards).
#' VP dev cards are kept secret until the player claims victory, so they are
#' not added to player$vp during normal play.  This function returns the full
#' total: visible VP + VP cards in hand + VP cards drawn this turn (also
#' secret).
#'
#' Use this function whenever deciding whether a player has won (>= 10 VP)
#' because a player can win by revealing multiple secret VP cards at once.
#'
#' @param player Player list.
#' @return Integer total VP.
compute_vp <- function(player) {
  player$vp +
    player$dev_cards[["victory_point"]] +
    player$dev_cards_new[["victory_point"]]
}

#' Check whether a player has reached the winning condition.
#'
#' A player wins when their true VP total (including hidden VP cards) reaches
#' or exceeds 10.  compute_vp() ensures hidden cards are counted.
#'
#' @param player Player list.
#' @return TRUE if compute_vp(player) >= 10.
has_won <- function(player) {
  compute_vp(player) >= 10L
}


# =============================================================================
# Game initialisation helpers (called by game.R during setup)
# =============================================================================

#' Grant starting resources from a player's second initial settlement.
#'
#' At game start, after placing their second settlement, each player receives
#' 1 resource card for each terrain hex adjacent to that settlement.
#' Desert hexes produce nothing; all other terrain yields their standard
#' resource.
#'
#' Relies on hexes_at_intersection() from board.R to find the adjacent hexes.
#'
#' @param player          Player list.
#' @param board           Board list from generate_board() (board.R).
#' @param intersection_id Integer; intersection ID of the second settlement.
#' @return Updated player list with starting resources added.
grant_initial_resources <- function(player, board, intersection_id) {
  hex_ids <- hexes_at_intersection(board, intersection_id)

  for (hid in hex_ids) {
    hex <- board$hexes[[hid]]
    # Desert (NA resource) yields nothing; robber on desert is irrelevant here.
    if (!is.na(hex$resource)) {
      player <- add_resource(player, hex$resource, 1L)
    }
  }

  player
}

#' Create the initial list of N player objects, one per strategy name.
#'
#' Assigns IDs 1..N matching the order of strategy_names.  Each player starts
#' in the default empty state from make_player().
#'
#' @param strategy_names Character vector of strategy labels, one per player.
#' @return A list of player objects, indexed 1..length(strategy_names).
init_players <- function(strategy_names) {
  lapply(seq_along(strategy_names), function(i) {
    make_player(id = i, strategy_name = strategy_names[[i]])
  })
}


# =============================================================================
# Player summary utility
# =============================================================================

#' Produce a one-row data.frame summarising a player's current state.
#'
#' Useful for logging turn-by-turn game progress, debugging strategy
#' behaviour, and producing the per-game result rows consumed by analysis.R.
#'
#' @param player Player list.
#' @return A data.frame with one row and columns for all key state fields.
player_summary <- function(player) {
  data.frame(
    id               = player$id,
    strategy         = player$strategy_name,
    # Individual resource counts
    lumber           = player$resources[["lumber"]],
    brick            = player$resources[["brick"]],
    wool             = player$resources[["wool"]],
    grain            = player$resources[["grain"]],
    ore              = player$resources[["ore"]],
    total_resources  = count_resources(player),
    # Piece counts
    roads            = length(player$road_locations),
    settlements      = length(player$settlement_locations),
    cities           = length(player$city_locations),
    # Dev card totals (playable hand only; new cards are not revealed)
    knights_in_hand  = player$dev_cards[["knight"]],
    knights_played   = player$knights_played,
    vp_cards         = player$dev_cards[["victory_point"]],
    # VP
    vp_public        = player$vp,
    vp_total         = compute_vp(player),
    # Special cards
    has_longest_road = player$has_longest_road,
    has_largest_army = player$has_largest_army,
    stringsAsFactors = FALSE
  )
}
