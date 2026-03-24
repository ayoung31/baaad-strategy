# =============================================================================
# game.R
# Game loop orchestration for the Catan sheep-strategy simulation.
#
# This module wires together board.R, player.R, and strategy.R into a complete
# playable game.  It owns all state mutation: rolling dice, distributing
# resources, enforcing the robber, executing actions returned by strategies,
# and tracking the two special cards (Longest Road, Largest Army).
#
# Entry point: run_game(strategies, board = NULL, seed = NULL)
#
# Dependencies (must be sourced first): board.R, player.R, strategy.R
# =============================================================================


# =============================================================================
# Dev-card deck
# =============================================================================

#' Build a shuffled development card deck.
#'
#' Uses DEV_CARD_COUNTS from player.R to know how many of each card to include.
#' The returned deck is a character vector; index 1 is the top of the deck.
#'
#' @return Character vector of length 25, randomly shuffled.
make_deck <- function() {
  # rep() expands each card type name by its count, producing a flat vector.
  deck <- rep(names(DEV_CARD_COUNTS), times = DEV_CARD_COUNTS)
  sample(deck)  # shuffle in place
}

#' Draw the top card from the deck.
#'
#' @param deck Character vector (the current deck).
#' @return Named list with:
#'   - `card`: Character card type drawn, or NA_character_ if the deck is empty.
#'   - `deck`: Updated (shorter) deck.
draw_from_deck <- function(deck) {
  if (length(deck) == 0L) return(list(card = NA_character_, deck = deck))
  list(card = deck[[1L]], deck = deck[-1L])
}


# =============================================================================
# Resource production
# =============================================================================

#' Distribute resources produced by a dice roll to all players.
#'
#' Calls compute_production() (board.R) to get the (player, resource, amount)
#' table, then applies add_resource() to each affected player.
#'
#' @param board   Board list.
#' @param players List of player objects.
#' @param roll    Integer dice total (must not be 7; caller filters this).
#' @return Updated players list.
distribute_resources <- function(board, players, roll) {
  production <- compute_production(board, roll)
  if (nrow(production) == 0L) return(players)

  for (k in seq_len(nrow(production))) {
    pid    <- production$player_id[k]
    res    <- production$resource[k]
    amount <- production$amount[k]
    players[[pid]] <- add_resource(players[[pid]], res, amount)
  }
  players
}


# =============================================================================
# Robber (roll of 7)
# =============================================================================

#' Handle a roll of 7: all over-limit players discard, then active player
#' moves the robber and optionally steals a card.
#'
#' Discard step: every player with more than 7 resource cards discards down to
#' half (rounded down) using their strategy's `choose_discard` preference.
#'
#' Placement step: the active player calls `choose_robber_placement` (strategy.R)
#' to pick a hex, then `choose_steal_victim` to pick a victim.
#'
#' @param board     Board list.
#' @param players   List of player objects.
#' @param active_id Integer index of the player who rolled 7.
#' @return Named list with updated `board` and `players`.
apply_robber <- function(board, players, active_id) {
  # --- Discard step ---
  # Every player (including the active player) with > 7 cards must discard.
  for (i in seq_along(players)) {
    if (must_discard(players[[i]])) {
      players[[i]] <- choose_discard(players[[i]], players[[i]]$strategy_name)
    }
  }

  # --- Robber placement ---
  active_player <- players[[active_id]]
  hex_id <- choose_robber_placement(board, active_player, players)
  board  <- move_robber(board, hex_id)

  # --- Steal ---
  victim_id <- choose_steal_victim(board, active_player, players, hex_id)
  if (!is.na(victim_id)) {
    result           <- steal_resource(players[[active_id]], players[[victim_id]])
    players[[active_id]]  <- result$thief
    players[[victim_id]]  <- result$victim
  }

  list(board = board, players = players)
}


# =============================================================================
# Special card updates
# =============================================================================

#' Recompute Longest Road after any road placement and transfer the card if
#' another player has surpassed the current holder.
#'
#' Rules:
#'   - Minimum road length to claim the card is LONGEST_ROAD_MIN (5 segments).
#'   - A player steals the card only by strictly exceeding the current holder.
#'   - If no one holds it yet, it is awarded to the first player who reaches 5.
#'   - Ties do not transfer the card (the holder keeps it on equal length).
#'
#' @param board   Board list (road ownership comes from edges).
#' @param players List of player objects.
#' @return Updated players list.
update_longest_road <- function(board, players) {
  n <- length(players)

  # Identify the current holder (at most one player can hold this at a time).
  current_holder <- NA_integer_
  for (i in seq_len(n)) {
    if (players[[i]]$has_longest_road) { current_holder <- i; break }
  }

  # Compute every player's current longest road length.
  road_lengths <- vapply(seq_len(n), function(i) longest_road(board, i), integer(1L))

  if (is.na(current_holder)) {
    # No one holds the card yet — award to whoever first reaches 5+.
    # In case of a tie on the very first award, give it to the lowest-index
    # player (consistent with original Catan rule ambiguity resolution).
    best_length <- max(road_lengths)
    if (best_length >= LONGEST_ROAD_MIN) {
      # First player to reach best_length gets the card.
      first_best <- which(road_lengths == best_length)[1L]
      players[[first_best]] <- award_longest_road(players[[first_best]])
    }
  } else {
    # Existing holder: only transfer if someone strictly exceeds their length.
    holder_length <- road_lengths[current_holder]
    for (i in seq_len(n)) {
      if (i == current_holder) next
      if (road_lengths[i] > holder_length && road_lengths[i] >= LONGEST_ROAD_MIN) {
        players[[current_holder]] <- revoke_longest_road(players[[current_holder]])
        players[[i]]              <- award_longest_road(players[[i]])
        break  # only one player can steal it per road placement
      }
    }
  }

  players
}

#' Update Largest Army after a knight is played.
#'
#' Rules:
#'   - Minimum knights played to claim the card is LARGEST_ARMY_MIN (3).
#'   - A player steals the card only by strictly exceeding the holder.
#'   - Only the active player (who just played the knight) can trigger a change.
#'
#' @param players   List of player objects.
#' @param active_id Integer index of the player who just played a knight.
#' @return Updated players list.
update_largest_army <- function(players, active_id) {
  n <- length(players)

  # Identify the current holder.
  current_holder <- NA_integer_
  for (i in seq_len(n)) {
    if (players[[i]]$has_largest_army) { current_holder <- i; break }
  }

  p <- players[[active_id]]

  if (is.na(current_holder)) {
    # No holder yet: award if the active player has reached the minimum.
    if (p$knights_played >= LARGEST_ARMY_MIN) {
      players[[active_id]] <- award_largest_army(p)
    }
  } else if (active_id != current_holder) {
    # Transfer only if the active player strictly beats the holder.
    if (p$knights_played > players[[current_holder]]$knights_played) {
      players[[current_holder]] <- revoke_largest_army(players[[current_holder]])
      players[[active_id]]      <- award_largest_army(p)
    }
  }
  # If active_id IS the current holder, nothing changes (they already own it).

  players
}


# =============================================================================
# Action dispatch
# =============================================================================

#' Apply a single action returned by a strategy's choose_action().
#'
#' Mutates board, players, and/or deck based on the action type and returns
#' the updated triple.  The "done" sentinel is NOT handled here — the caller
#' (run_action_phase) stops the loop when it sees "done".
#'
#' @param action    Named list with a `type` field (see strategy.R docs).
#' @param board     Board list.
#' @param players   List of player objects.
#' @param deck      Character vector dev-card deck.
#' @param active_id Integer index of the acting player.
#' @return Named list with `board`, `players`, `deck`.
apply_action <- function(action, board, players, deck, active_id) {
  p <- players[[active_id]]

  if (action$type == "build_road") {
    # Deduct costs, record road on board and in player state.
    p     <- do_build(p, "road")
    board <- place_road(board, action$edge_id, active_id)
    p     <- add_road_location(p, action$edge_id)
    players[[active_id]] <- p
    # Road placements can change Longest Road ownership.
    players <- update_longest_road(board, players)

  } else if (action$type == "build_settlement") {
    p     <- do_build(p, "settlement")
    board <- place_structure(board, action$intersection_id, active_id, "settlement")
    p     <- add_settlement_location(p, action$intersection_id)
    players[[active_id]] <- p

  } else if (action$type == "build_city") {
    p     <- do_build(p, "city")
    board <- place_structure(board, action$intersection_id, active_id, "city")
    p     <- upgrade_to_city(p, action$intersection_id)
    players[[active_id]] <- p

  } else if (action$type == "buy_dev_card") {
    # Deduct resources, draw the top card, give it to the player.
    p        <- do_build(p, "dev_card")
    drawn    <- draw_from_deck(deck)
    deck     <- drawn$deck
    if (!is.na(drawn$card)) {
      p <- draw_dev_card(p, drawn$card)
    }
    players[[active_id]] <- p

  } else if (action$type == "trade") {
    # Bank or port trade; do_trade handles rate validation.
    players[[active_id]] <- do_trade(p, action$give, action$give_count,
                                     action$receive)

  } else if (action$type == "play_knight") {
    # Spend the card, move robber, optionally steal.
    p     <- spend_dev_card(p, "knight")
    board <- move_robber(board, action$hex_id)
    players[[active_id]] <- p
    if (!is.na(action$victim_id)) {
      result                    <- steal_resource(players[[active_id]],
                                                  players[[action$victim_id]])
      players[[active_id]]      <- result$thief
      players[[action$victim_id]] <- result$victim
    }
    # Knight may trigger Largest Army transfer.
    players <- update_largest_army(players, active_id)

  } else if (action$type == "play_year_of_plenty") {
    players[[active_id]] <- play_year_of_plenty(p, action$res1, action$res2)

  } else if (action$type == "play_monopoly") {
    # play_monopoly operates on the full players list (drains all opponents).
    players <- play_monopoly(players, active_id, action$resource)

  } else if (action$type == "play_road_building") {
    # Spend the card, then place two free roads (no resource cost).
    p <- play_road_building(p)
    players[[active_id]] <- p
    for (eid in c(action$edge1, action$edge2)) {
      board <- place_road(board, eid, active_id)
      players[[active_id]] <- add_road_location(players[[active_id]], eid)
    }
    players <- update_longest_road(board, players)
  }
  # Unknown types are silently ignored (defensive: strategies should not produce
  # them, but this prevents a hard crash in edge cases).

  list(board = board, players = players, deck = deck)
}


# =============================================================================
# Action phase
# =============================================================================

#' Run the full action phase for one player's turn.
#'
#' Calls strategy$choose_action() in a loop until the strategy returns
#' list(type = "done") or the loop limit is reached (safety against infinite
#' loops in buggy strategies).
#'
#' @param board     Board list.
#' @param players   List of player objects.
#' @param deck      Character vector dev-card deck.
#' @param active_id Integer index of the active player.
#' @param strategy  Strategy list (four-function interface from strategy.R).
#' @param game_state Named list passed to choose_action().
#' @return Named list with updated `board`, `players`, `deck`.
run_action_phase <- function(board, players, deck, active_id, strategy,
                             game_state) {
  # Guard against runaway strategies; 50 actions per turn is well above the
  # Catan maximum in any realistic game.
  max_actions <- 50L

  for (step in seq_len(max_actions)) {
    action <- strategy$choose_action(board, players[[active_id]], game_state)

    if (action$type == "done") break

    result   <- apply_action(action, board, players, deck, active_id)
    board    <- result$board
    players  <- result$players
    deck     <- result$deck

    # Refresh game_state after each action so the strategy sees the latest
    # deck size and player states on its next call.
    game_state$players   <- players
    game_state$deck_size <- length(deck)
  }

  list(board = board, players = players, deck = deck)
}


# =============================================================================
# Initial placement (reverse snake draft)
# =============================================================================

#' Run the initial settlement and road placement for all players.
#'
#' Standard Catan reverse snake draft:
#'   Forward pass  (1 → n): each player places their first settlement + road.
#'   Reverse pass  (n → 1): each player places their second settlement + road,
#'                           then immediately receives resources from that spot.
#'
#' Each setup road must connect directly to the settlement placed that same
#' turn (enforced via the must_connect_to parameter in choose_road_placement).
#'
#' @param board      Board list.
#' @param players    List of player objects.
#' @param strategies List of strategy objects (same length as players).
#' @return Named list with updated `board` and `players`.
run_initial_placement <- function(board, players, strategies) {
  n        <- length(players)
  taken_ids <- integer(0)

  # Helper game_state for road placement calls during setup.
  # Turn 0 signals to strategies that we are in the setup phase.
  setup_game_state <- function(players, active_id) {
    list(players = players, turn = 0L, active_id = active_id, deck_size = 25L)
  }

  # --- Forward pass: players 1 → n ---
  for (i in seq_len(n)) {
    strat  <- strategies[[i]]
    player <- players[[i]]

    # Place first settlement.
    int_id <- strat$choose_initial_placement(board, player, taken_ids)
    board  <- place_structure(board, int_id, i, "settlement")
    player <- add_settlement_location(player, int_id)
    taken_ids <- c(taken_ids, int_id)

    # Place road adjacent to that settlement.
    edge_id <- strat$choose_road_placement(
      board, player, setup_game_state(players, i),
      must_connect_to = int_id
    )
    board  <- place_road(board, edge_id, i)
    player <- add_road_location(player, edge_id)

    players[[i]] <- player
  }

  # --- Reverse pass: players n → 1 ---
  for (i in rev(seq_len(n))) {
    strat  <- strategies[[i]]
    player <- players[[i]]

    # Place second settlement.
    int_id <- strat$choose_second_placement(board, player, taken_ids)
    board  <- place_structure(board, int_id, i, "settlement")
    player <- add_settlement_location(player, int_id)
    taken_ids <- c(taken_ids, int_id)

    # Place road adjacent to that settlement.
    edge_id <- strat$choose_road_placement(
      board, player, setup_game_state(players, i),
      must_connect_to = int_id
    )
    board  <- place_road(board, edge_id, i)
    player <- add_road_location(player, edge_id)

    # Grant starting resources from the second settlement's adjacent hexes.
    player <- grant_initial_resources(player, board, int_id)

    players[[i]] <- player
  }

  list(board = board, players = players)
}


# =============================================================================
# Single turn
# =============================================================================

#' Execute one complete player turn.
#'
#' Steps:
#'   1. Advance dev cards (moves cards bought last turn into the playable hand).
#'   2. Roll two dice.
#'   3a. If 7: apply_robber (discards + robber move + steal).
#'   3b. Otherwise: distribute_resources.
#'   4. Run the action phase (strategy chooses builds, trades, dev card plays).
#'
#' @param board      Board list.
#' @param players    List of player objects.
#' @param deck       Character vector dev-card deck.
#' @param active_id  Integer index of the player taking the turn.
#' @param strategies List of strategy objects.
#' @param turn       Integer turn number (for game_state).
#' @return Named list with updated `board`, `players`, `deck`.
run_turn <- function(board, players, deck, active_id, strategies, turn) {
  # Step 1: bring last turn's dev card purchases into the playable hand.
  players[[active_id]] <- advance_dev_cards(players[[active_id]])

  # Step 2: roll the dice.
  roll <- sample(1L:6L, 1L) + sample(1L:6L, 1L)

  # Step 3: resolve the roll.
  if (roll == 7L) {
    result  <- apply_robber(board, players, active_id)
    board   <- result$board
    players <- result$players
  } else {
    players <- distribute_resources(board, players, roll)
  }

  # Step 4: action phase.
  game_state <- list(
    players   = players,
    turn      = turn,
    active_id = active_id,
    deck_size = length(deck)
  )

  result  <- run_action_phase(board, players, deck, active_id,
                              strategies[[active_id]], game_state)
  board   <- result$board
  players <- result$players
  deck    <- result$deck

  list(board = board, players = players, deck = deck)
}


# =============================================================================
# Game result
# =============================================================================

#' Construct a game result summary list.
#'
#' @param winner_id Integer player ID of the winner, or NA_integer_ for stalemate.
#' @param players   Final list of player objects.
#' @param turn      Integer number of individual player turns elapsed.
#' @param board     Final board state list.
#' @return Named list with winner_id, turns, players summary data.frame,
#'   player_objects (raw player list), and board.
make_game_result <- function(winner_id, players, turn, board) {
  # Build a per-player summary data.frame for easy analysis.
  summary_rows <- lapply(players, function(p) {
    data.frame(
      id            = p$id,
      strategy      = p$strategy_name,
      vp_visible    = p$vp,
      vp_total      = compute_vp(p),
      settlements   = length(p$settlement_locations),
      cities        = length(p$city_locations),
      roads         = length(p$road_locations),
      knights       = p$knights_played,
      longest_road  = p$has_longest_road,
      largest_army  = p$has_largest_army,
      stringsAsFactors = FALSE
    )
  })

  list(
    winner_id      = winner_id,
    turns          = turn,
    players        = do.call(rbind, summary_rows),
    player_objects = players,
    board          = board
  )
}


# =============================================================================
# Main entry point
# =============================================================================

#' Run a complete game of Catan between the provided strategies.
#'
#' @param strategies Named list of strategy objects, one per player.
#'   Names become each player's strategy_name in the result.
#'   Length determines the number of players (2–4 recommended).
#' @param board  Optional pre-built board list (from generate_board()).
#'   If NULL, a fresh random board is generated each call.
#' @param seed   Optional integer random seed for reproducibility.
#'   Affects both board generation (if board=NULL) and all in-game randomness.
#' @param max_turns Integer; maximum individual player turns before declaring a
#'   stalemate and returning NA as the winner. Defaults to 500.
#' @return A game result list from make_game_result():
#'   - `winner_id`:      integer player ID (1-indexed) or NA for stalemate.
#'   - `turns`:          total individual player turns elapsed.
#'   - `players`:        data.frame summarising each player's final state.
#'   - `player_objects`: raw player list (for use with plot_board()).
#'   - `board`:          final board state list (for use with plot_board()).
run_game <- function(strategies, board = NULL, seed = NULL, max_turns = 500L) {
  if (!is.null(seed)) set.seed(seed)

  # --- Setup ---
  if (is.null(board)) board <- generate_board()

  # Use strategy list names as strategy_name labels; fall back to "player_N".
  strategy_names <- names(strategies)
  if (is.null(strategy_names)) {
    strategy_names <- paste0("player", seq_along(strategies))
  }

  # Randomise seating order so no strategy is structurally advantaged by its
  # position in the snake draft (seat 3 in a 3-player game has the best
  # consecutive draft picks: 3rd forward, 1st reverse).
  n            <- length(strategies)
  seat_order   <- sample(seq_len(n))
  strategies   <- strategies[seat_order]
  strategy_names <- strategy_names[seat_order]

  players <- init_players(strategy_names)
  deck    <- make_deck()

  # --- Initial placement (reverse snake draft) ---
  init_result <- run_initial_placement(board, players, strategies)
  board   <- init_result$board
  players <- init_result$players

  # --- Main game loop ---
  turn <- 0L

  repeat {
    # Track who (if anyone) first reaches 10 VP this round. We finish the full
    # round before declaring a winner so every player gets an equal number of
    # turns — matching the standard Catan rule that play continues until the
    # end of the round in which someone first hits 10 VP.
    winner_this_round <- NA_integer_

    for (i in seq_len(n)) {
      turn <- turn + 1L

      result  <- run_turn(board, players, deck, i, strategies, turn)
      board   <- result$board
      players <- result$players
      deck    <- result$deck

      # Record the first player to hit 10 VP, but keep playing the round.
      if (is.na(winner_this_round) &&
          compute_vp(players[[i]]) >= 10L) {
        winner_this_round <- i
      }
    }

    # After all players have taken their turn, declare the winner.
    if (!is.na(winner_this_round)) {
      # If multiple players reached 10 VP in the same round, the one who got
      # there first (lowest seat index after shuffling) wins.
      for (i in seq_len(n)) {
        if (compute_vp(players[[i]]) >= 10L) {
          return(make_game_result(i, players, turn, board))
        }
      }
    }

    # Stalemate guard: abort extremely long games.
    if (turn >= max_turns) {
      return(make_game_result(NA_integer_, players, turn, board))
    }
  }
}
