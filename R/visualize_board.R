# =============================================================================
# visualize_board.R
# Render a generated Catan board as a ggplot2 graphic.
#
# Usage:
#   source("R/board.R")
#   source("R/visualize_board.R")
#   board <- generate_board(seed = 42)
#   plot_board(board)
# =============================================================================

library(ggplot2)
library(patchwork)

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------

TERRAIN_COLORS <- c(
  forest   = "#3a7d2c",
  hills    = "#b84a1a",
  pasture  = "#8ecf3a",
  fields   = "#e8c030",
  mountain = "#8a8a9a",
  desert   = "#e8d898"
)

TERRAIN_LABELS <- c(
  forest   = "Lumber",
  hills    = "Brick",
  pasture  = "Wool",
  fields   = "Grain",
  mountain = "Ore",
  desert   = "Desert"
)

# Classic Catan player colours (red, blue, white, orange).
PLAYER_COLORS <- c(
  "1" = "#CC2200",
  "2" = "#1155CC",
  "3" = "#FFFFFF",
  "4" = "#FF8800"
)

# Standard 3-4-5-4-3 reading-order mapping of hex IDs to grid positions.
HEX_GRID <- local({
  rows <- c(rep(1L,3), rep(2L,4), rep(3L,5), rep(4L,4), rep(5L,3))
  cols <- c(1:3, 1:4, 1:5, 1:4, 1:3)
  data.frame(hex_id = 1:19, row = rows, col_in_row = cols)
})

ROW_WIDTHS <- c(3L, 4L, 5L, 4L, 3L)

# -----------------------------------------------------------------------------
# Geometry helpers
# -----------------------------------------------------------------------------

# Convert a (row, col_in_row) grid position to pixel (x, y) for a pointy-top
# hexagon grid.  Row 3 (the widest) sits at y = 0; positive y is up.
hex_center_xy <- function(row, col_in_row, size = 1) {
  w <- sqrt(3) * size                            # horizontal distance between centres
  y <- -(row - 3L) * 1.5 * size
  x <- (col_in_row - (ROW_WIDTHS[row] + 1L) / 2) * w
  c(x = x, y = y)
}

# Return a 6-row data.frame of the vertices of a pointy-top hexagon.
hex_polygon <- function(cx, cy, size = 1) {
  angles <- (30 + 60 * 0:5) * pi / 180
  data.frame(x = cx + size * cos(angles),
             y = cy + size * sin(angles))
}

# -----------------------------------------------------------------------------
# Outer boundary helpers
# -----------------------------------------------------------------------------

# Internal: tally every hex edge and return only those appearing exactly once
# (unshared = outer).  Shared by build_ocean_polygon and coastal_int_coords.
outer_hex_edges <- function(size) {
  prec   <- 8L
  pt_key <- function(x, y) paste(round(x, prec), round(y, prec), sep = ",")
  tally  <- list()

  for (i in seq_len(nrow(HEX_GRID))) {
    ctr   <- hex_center_xy(HEX_GRID$row[i], HEX_GRID$col_in_row[i], size)
    verts <- hex_polygon(ctr["x"], ctr["y"], size)
    n     <- nrow(verts)
    for (k in seq_len(n)) {
      a   <- k
      b   <- (k %% n) + 1L
      va  <- pt_key(verts$x[a], verts$y[a])
      vb  <- pt_key(verts$x[b], verts$y[b])
      key <- paste(sort(c(va, vb)), collapse = "|")
      if (is.null(tally[[key]])) {
        tally[[key]] <- list(count = 1L, x1 = verts$x[a], y1 = verts$y[a],
                             x2 = verts$x[b], y2 = verts$y[b])
      } else {
        tally[[key]]$count <- tally[[key]]$count + 1L
      }
    }
  }
  Filter(function(e) e$count == 1L, tally)
}

# Build the ocean background polygon, expanded 6% outward for a thin border.
build_ocean_polygon <- function(size) {
  outer  <- outer_hex_edges(size)
  prec   <- 8L
  pt_key <- function(x, y) paste(round(x, prec), round(y, prec), sep = ",")

  used     <- logical(length(outer))
  result_x <- c(outer[[1]]$x1, outer[[1]]$x2)
  result_y <- c(outer[[1]]$y1, outer[[1]]$y2)
  used[1]  <- TRUE

  for (step in seq_len(length(outer) - 1L)) {
    curr <- pt_key(result_x[length(result_x)], result_y[length(result_y)])
    for (j in seq_along(outer)) {
      if (used[j]) next
      e <- outer[[j]]
      if (pt_key(e$x1, e$y1) == curr) {
        result_x <- c(result_x, e$x2); result_y <- c(result_y, e$y2)
        used[j] <- TRUE; break
      } else if (pt_key(e$x2, e$y2) == curr) {
        result_x <- c(result_x, e$x1); result_y <- c(result_y, e$y1)
        used[j] <- TRUE; break
      }
    }
  }

  cx <- mean(result_x); cy <- mean(result_y)
  data.frame(x = cx + (result_x - cx) * 1.06,
             y = cy + (result_y - cy) * 1.06)
}

# Compute pixel coordinates for all 30 coastal intersections.
#
# The 30 outer boundary vertices are sorted clockwise starting from the
# upper-left corner of the board (COASTAL_INTERSECTIONS[1] = intersection 1,
# which is the 150° vertex of the hex at row=1, col=1).  This establishes a
# 1-to-1 mapping between coastal intersection IDs and pixel positions.
#
# Returns a data.frame: int_id | x | y
coastal_int_coords <- function(size) {
  outer <- outer_hex_edges(size)
  prec  <- 8L

  # Collect unique outer vertex positions.
  all_pts <- do.call(rbind, lapply(outer, function(e) {
    rbind(c(e$x1, e$y1), c(e$x2, e$y2))
  }))
  keys    <- paste(round(all_pts[, 1], prec), round(all_pts[, 2], prec), sep = ",")
  all_pts <- all_pts[!duplicated(keys), , drop = FALSE]

  # COASTAL_INTERSECTIONS[1] = 150° vertex of the (row=1, col=1) hex.
  ctr1        <- hex_center_xy(1L, 1L, size)
  int1_x      <- ctr1["x"] + size * cos(150 * pi / 180)
  int1_y      <- ctr1["y"] + size * sin(150 * pi / 180)

  # Find the outer vertex nearest that position and use it as the start.
  dists       <- sqrt((all_pts[, 1] - int1_x)^2 + (all_pts[, 2] - int1_y)^2)
  start_idx   <- which.min(dists)
  start_angle <- atan2(all_pts[start_idx, 2], all_pts[start_idx, 1])

  # (start_angle - angle) mod 2π = 0 at start, increases clockwise.
  angles     <- atan2(all_pts[, 2], all_pts[, 1])
  adj_angles <- (start_angle - angles) %% (2 * pi)
  sorted_pts <- all_pts[order(adj_angles), , drop = FALSE]

  data.frame(int_id = COASTAL_INTERSECTIONS,
             x      = sorted_pts[, 1],
             y      = sorted_pts[, 2],
             stringsAsFactors = FALSE)
}

# -----------------------------------------------------------------------------
# Data builders
# -----------------------------------------------------------------------------

build_polygon_df <- function(board, size) {
  do.call(rbind, lapply(seq_len(nrow(HEX_GRID)), function(i) {
    hid    <- HEX_GRID$hex_id[i]
    ctr    <- hex_center_xy(HEX_GRID$row[i], HEX_GRID$col_in_row[i], size)
    verts  <- hex_polygon(ctr["x"], ctr["y"], size * 0.97)
    h      <- board$hexes[[hid]]
    verts$group      <- hid
    verts$terrain    <- h$terrain
    verts$has_robber <- h$has_robber
    verts
  }))
}

build_label_df <- function(board, size) {
  do.call(rbind, lapply(seq_len(nrow(HEX_GRID)), function(i) {
    hid  <- HEX_GRID$hex_id[i]
    ctr  <- hex_center_xy(HEX_GRID$row[i], HEX_GRID$col_in_row[i], size)
    h    <- board$hexes[[hid]]
    data.frame(
      hex_id     = hid,
      x          = ctr["x"],
      y          = ctr["y"],
      token      = if (is.na(h$token)) NA_character_ else as.character(h$token),
      pips       = h$pips,
      terrain    = h$terrain,
      has_robber = h$has_robber,
      stringsAsFactors = FALSE
    )
  }))
}

build_pip_df <- function(label_df, size) {
  rows <- lapply(seq_len(nrow(label_df)), function(i) {
    r <- label_df[i, ]
    if (is.na(r$token) || r$pips == 0L) return(NULL)
    n       <- r$pips
    offsets  <- seq(-(n - 1) / 2, (n - 1) / 2) * 0.11 * size
    data.frame(x = r$x + offsets, y = r$y - 0.08 * size, group = r$hex_id)
  })
  do.call(rbind, rows)
}

# Build a data.frame describing every port on the board.
#
# Scans consecutive pairs in COASTAL_INTERSECTIONS; if both share the same
# port definition the pair forms a port edge.  Uses coastal_int_coords to
# convert intersection IDs to pixel positions.
#
# Columns: label | lx, ly (label position) | x1,y1 | x2,y2 (endpoint pixels)
build_port_df <- function(board, size) {
  coords    <- coastal_int_coords(size)
  lookup_xy <- function(id) unlist(coords[coords$int_id == id, c("x", "y")])

  n    <- length(COASTAL_INTERSECTIONS)
  rows <- list()

  for (k in seq_len(n)) {
    id_a   <- COASTAL_INTERSECTIONS[k]
    id_b   <- COASTAL_INTERSECTIONS[(k %% n) + 1L]
    port_a <- board$intersections[[id_a]]$port
    port_b <- board$intersections[[id_b]]$port
    if (is.null(port_a) || is.null(port_b)) next
    if (!identical(port_a$resource, port_b$resource)) next
    if (port_a$rate != port_b$rate) next

    pa  <- lookup_xy(id_a)
    pb  <- lookup_xy(id_b)
    mx  <- (pa["x"] + pb["x"]) / 2
    my  <- (pa["y"] + pb["y"]) / 2
    d   <- sqrt(mx^2 + my^2)
    lbl <- if (is.na(port_a$resource)) "3:1" else paste0("2:1\n", port_a$resource)

    rows[[length(rows) + 1L]] <- data.frame(
      label = lbl,
      lx    = mx + mx / d * 1.6 * size,   # label: pushed outward
      ly    = my + my / d * 1.6 * size,
      x1    = pa["x"], y1 = pa["y"],       # intersection A on boundary
      x2    = pb["x"], y2 = pb["y"],       # intersection B on boundary
      stringsAsFactors = FALSE
    )
  }
  if (length(rows) == 0) return(NULL)
  do.call(rbind, rows)
}

# -----------------------------------------------------------------------------
# Piece geometry helpers
# -----------------------------------------------------------------------------

#' Precompute pixel (x, y) positions of all 6 corners for each of the 19 hexes.
#'
#' Uses the same pointy-top angle sequence as hex_polygon() so the corner
#' positions are geometrically consistent with the rendered tiles.
#'
#' @param size  Hex size scalar (must match the value passed to plot_board).
#' @return A list of length 19.  Element [[i]] is itself a list of 6 named
#'   numeric vectors, each with elements \code{x} and \code{y}, corresponding
#'   to hex_polygon corners k = 0..5 (angles 30°, 90°, …, 330°).
build_hex_corners <- function(size) {
  angles_rad <- (30 + 60 * 0:5) * pi / 180
  lapply(seq_len(nrow(HEX_GRID)), function(i) {
    ctr <- hex_center_xy(HEX_GRID$row[i], HEX_GRID$col_in_row[i], size)
    lapply(0:5, function(k) {
      c(x = unname(ctr["x"]) + size * cos(angles_rad[k + 1L]),
        y = unname(ctr["y"]) + size * sin(angles_rad[k + 1L]))
    })
  })
}

#' For each of the 54 intersection IDs, find every hex that contains it.
#'
#' Scans HEX_INTERSECTIONS once and inverts the mapping so that, given an
#' intersection ID, we can immediately look up which hexes (1-19) share it.
#' Intersection IDs > 54 (sentinel values in the bottom rows) are ignored.
#'
#' @return A list of length 54.  Element [[vid]] is an integer vector of hex
#'   IDs (values in 1-19) whose HEX_INTERSECTIONS entry contains \code{vid}.
#'   Elements for IDs with no containing hex are \code{integer(0)}.
build_hex_membership <- function() {
  membership <- vector("list", 54L)
  for (i in seq_along(membership)) membership[[i]] <- integer(0)

  for (hid in seq_along(HEX_INTERSECTIONS)) {
    for (vid in HEX_INTERSECTIONS[[hid]]) {
      if (vid > 54L) next
      membership[[vid]] <- c(membership[[vid]], hid)
    }
  }
  membership
}

#' Compute pixel (x, y) coordinates for all 54 intersections.
#'
#' Each intersection is a shared corner of 1-3 hexes.  We iterate over every
#' hex, map its 6 corners to the intersection IDs in HEX_INTERSECTIONS, and
#' accumulate a running average of the pixel position (contributions from
#' adjacent hexes are geometrically identical up to floating-point rounding).
#'
#' @param size  Hex size scalar (must match the value passed to plot_board).
#' @return A data.frame with columns intersection_id, x, y.
build_intersection_coords <- function(size) {
  membership <- build_hex_membership()
  # Angles (radians) for HEX_INTERSECTIONS positions 1..6: N, NE, SE, S, SW, NW
  hex_angles <- c(90, 30, 330, 270, 210, 150) * pi / 180
  xs <- rep(NA_real_, 54)
  ys <- rep(NA_real_, 54)
  for (vid in seq_len(54L)) {
    hex_ids <- membership[[vid]]
    if (length(hex_ids) == 0L) next
    hid <- hex_ids[1L]
    k   <- which(HEX_INTERSECTIONS[[hid]] == vid)   # 1-based position (1=N ... 6=NW)
    ctr <- hex_center_xy(HEX_GRID$row[hid], HEX_GRID$col_in_row[hid], size)
    xs[vid] <- unname(ctr["x"]) + size * cos(hex_angles[k])
    ys[vid] <- unname(ctr["y"]) + size * sin(hex_angles[k])
  }
  data.frame(intersection_id = 1:54, x = xs, y = ys,
             stringsAsFactors = FALSE)
}

#' Build a data.frame of road segments from the board state.
#'
#' @param board      A board list from generate_board().
#' @param int_coords data.frame from build_intersection_coords().
#' @return data.frame with columns x, y, xend, yend, player_id, or NULL.
build_road_df <- function(board, int_coords) {
  rows <- list()
  for (edge in board$edges) {
    if (is.na(edge$owner)) next
    c1 <- int_coords[int_coords$intersection_id == edge$ends[1], ]
    c2 <- int_coords[int_coords$intersection_id == edge$ends[2], ]
    if (nrow(c1) == 0 || nrow(c2) == 0 || is.na(c1$x) || is.na(c2$x)) next
    rows[[length(rows) + 1L]] <- data.frame(
      x         = c1$x, y         = c1$y,
      xend      = c2$x, yend      = c2$y,
      player_id = as.character(edge$owner),
      stringsAsFactors = FALSE
    )
  }
  if (length(rows) == 0L) return(NULL)
  do.call(rbind, rows)
}

#' Build a data.frame of settlement and city positions from the board state.
#'
#' @param board      A board list from generate_board().
#' @param int_coords data.frame from build_intersection_coords().
#' @return data.frame with columns x, y, structure, player_id, or NULL.
build_structure_df <- function(board, int_coords) {
  rows <- list()
  for (int in board$intersections) {
    if (int$structure == "none" || is.na(int$owner)) next
    coord <- int_coords[int_coords$intersection_id == int$id, ]
    if (nrow(coord) == 0L || is.na(coord$x)) next
    rows[[length(rows) + 1L]] <- data.frame(
      x         = coord$x,
      y         = coord$y,
      structure = int$structure,
      player_id = as.character(int$owner),
      stringsAsFactors = FALSE
    )
  }
  if (length(rows) == 0L) return(NULL)
  do.call(rbind, rows)
}

# -----------------------------------------------------------------------------
# Main plotting function
# -----------------------------------------------------------------------------

#' Plot a Catan board.
#'
#' @param board       A board list from \code{generate_board()}.
#' @param size        Hex size scalar (default 1). Increase for a larger plot.
#' @param ports       Logical; if TRUE, annotate port positions (default TRUE).
#' @param show_pieces Logical; if TRUE, draw roads/settlements/cities from the
#'                    board state (default TRUE). Only visible when pieces have
#'                    been placed via place_structure() / place_road().
#' @return A ggplot object.
plot_board <- function(board, size = 1, ports = TRUE, show_pieces = TRUE,
                       players = NULL, player_labels = NULL) {
  # Auto-derive labels from players list if provided and player_labels not set
  if (!is.null(players) && is.null(player_labels)) {
    player_labels <- setNames(
      vapply(players, function(p) paste0("Player ", p$id, " (", p$strategy_name, ")"), character(1)),
      vapply(players, function(p) as.character(p$id), character(1))
    )
  }
  poly_df  <- build_polygon_df(board, size)
  label_df <- build_label_df(board, size)
  pip_df   <- build_pip_df(label_df, size)

  has_token  <- !is.na(label_df$token)
  token_df   <- label_df[has_token, ]
  red_tokens <- token_df$token %in% c("6", "8")

  p <- ggplot() +

    # Ocean background — true outer boundary of the 19 hex tiles
    geom_polygon(
      data = build_ocean_polygon(size),
      aes(x = x, y = y),
      fill = "#5b9ec9", color = "#3a7aaa", linewidth = 1
    ) +

    # Hex tiles
    geom_polygon(
      data = poly_df,
      aes(x = x, y = y, group = group, fill = terrain),
      color = "#2a1a08", linewidth = 0.6
    ) +
    scale_fill_manual(
      values = TERRAIN_COLORS,
      labels = TERRAIN_LABELS,
      name   = NULL
    ) +

    # Token circle background
    geom_point(
      data  = token_df,
      aes(x = x, y = y + 0.07 * size),
      shape = 21, size = 9 * size,
      fill  = "#fffff0", color = "#2a1a08", stroke = 0.7
    ) +

    # Token number (6 and 8 in red — highest-pip numbers)
    geom_text(
      data = token_df[!red_tokens, ],
      aes(x = x, y = y + 0.18 * size, label = token),
      fontface = "bold", size = 3.2 * size, color = "#1a1a1a"
    ) +
    geom_text(
      data = token_df[red_tokens, ],
      aes(x = x, y = y + 0.18 * size, label = token),
      fontface = "bold", size = 3.2 * size, color = "#bb1111"
    ) +

    # Pip dots
    {if (!is.null(pip_df) && nrow(pip_df) > 0)
      geom_point(
        data  = pip_df,
        aes(x = x, y = y, group = group),
        shape = 16, size = 0.8 * size, color = "#444444"
      )
    } +

    # Robber
    geom_label(
      data  = label_df[label_df$has_robber, ],
      aes(x = x, y = y - 0.42 * size, label = "ROBBER"),
      size       = 2.4 * size,
      fontface   = "bold",
      color      = "#cc0000",
      fill       = "#fff8f0",
      label.size = 0.3,
      label.padding = unit(0.15, "lines")
    ) +

    coord_equal(clip = "off")

  # ── Roads, settlements, cities ─────────────────────────────────────────────
  guide_pids <- character(0)   # captured for the unconditional guides() call below
  if (show_pieces) {
    int_coords   <- build_intersection_coords(size)
    road_df      <- build_road_df(board, int_coords)
    structure_df <- build_structure_df(board, int_coords)

    # Pre-resolve player colours to avoid conflicting ggplot2 fill/colour scales
    player_ids_present <- character(0)

    if (!is.null(road_df)) {
      road_df$colour <- PLAYER_COLORS[road_df$player_id]
      player_ids_present <- union(player_ids_present, road_df$player_id)
      # Black outline drawn first, then player colour on top
      p <- p +
        geom_segment(
          data = road_df,
          aes(x = x, y = y, xend = xend, yend = yend),
          colour = "#1a1a1a",
          linewidth = 1.8 * size, lineend = "round"
        ) +
        geom_segment(
          data = road_df,
          aes(x = x, y = y, xend = xend, yend = yend, colour = I(colour)),
          linewidth = 1.1 * size, lineend = "round"
        )
    }

    if (!is.null(structure_df)) {
      structure_df$fill_col <- PLAYER_COLORS[structure_df$player_id]
      player_ids_present <- union(player_ids_present, structure_df$player_id)

      p <- p +
        geom_point(
          data   = structure_df,
          aes(x = x, y = y, fill = I(fill_col), shape = structure),
          size   = 3.5 * size, stroke = 0.8, colour = "#1a1a1a"
        ) +
        scale_shape_manual(
          values = c("settlement" = 21, "city" = 23),
          name   = "Structure"
        )
    }

    # Player colour legend: invisible points with named colour scale
    if (length(player_ids_present) > 0) {
      pids       <- sort(player_ids_present)
      guide_pids <- pids                 # expose for guides() call below
      p_labels <- if (!is.null(player_labels)) {
        setNames(
          ifelse(is.na(player_labels[pids]),
                 paste("Player", pids),
                 player_labels[pids]),
          pids
        )
      } else {
        setNames(paste("Player", pids), pids)
      }
      legend_df <- data.frame(
        x         = rep(NA_real_, length(pids)),
        y         = rep(NA_real_, length(pids)),
        player_id = pids,
        stringsAsFactors = FALSE
      )
      p <- p +
        geom_point(
          data    = legend_df,
          aes(x = x, y = y, colour = player_id),
          shape   = 15, size = 4 * size, na.rm = TRUE
        ) +
        scale_colour_manual(
          values       = PLAYER_COLORS[pids],
          labels       = p_labels,
          breaks       = pids,
          name         = "Player",
          na.translate = FALSE
        )
    }
  }

  # Fix legend order unconditionally: Player (1) always above Terrain (2)
  if (length(guide_pids) > 0) {
    p <- p + guides(
      colour = guide_legend(
        order        = 1,
        override.aes = list(
          shape  = 22,
          size   = 3 * size,
          fill   = unname(PLAYER_COLORS[guide_pids]),
          colour = "#1a1a1a",
          stroke = 0.8
        )
      ),
      shape = guide_legend(
        order        = 2,
        override.aes = list(fill = "#888888", colour = "#1a1a1a", size = 3 * size)
      ),
      fill  = guide_legend(order = 3, override.aes = list(color = NA))
    )
  } else {
    p <- p + guides(fill = guide_legend(override.aes = list(color = NA)))
  }

  p <- p +
    theme_void(base_size = 11 * size) +
    theme(
      plot.title        = element_text(hjust = 0.5, face = "bold", size = 13 * size),
      plot.background   = element_rect(fill = "#d0eaf8", color = NA),
      legend.position   = "right",
      legend.key.size   = unit(0.6 * size, "lines"),
      legend.text       = element_text(size = 7 * size),
      plot.margin       = margin(10, 10, 10, 10)
    ) +
    labs(title = NULL)

  # Port indicators: dashed lines to both intersections + endpoint dots + label
  if (ports) {
    port_df <- tryCatch(build_port_df(board, size), error = function(e) NULL)
    if (!is.null(port_df) && nrow(port_df) > 0) {
      p <- p +
        geom_segment(
          data = port_df,
          aes(x = lx, y = ly, xend = x1, yend = y1),
          color = "#1a3a6a", linewidth = 0.4 * size, linetype = "dashed"
        ) +
        geom_segment(
          data = port_df,
          aes(x = lx, y = ly, xend = x2, yend = y2),
          color = "#1a3a6a", linewidth = 0.4 * size, linetype = "dashed"
        ) +
        geom_point(
          data  = port_df,
          aes(x = x1, y = y1),
          shape = 21, size = 2.5 * size,
          fill  = "#d8eef8", color = "#1a3a6a", stroke = 0.8
        ) +
        geom_point(
          data  = port_df,
          aes(x = x2, y = y2),
          shape = 21, size = 2.5 * size,
          fill  = "#d8eef8", color = "#1a3a6a", stroke = 0.8
        ) +
        geom_label(
          data          = port_df,
          aes(x = lx, y = ly, label = label),
          size          = 3.0 * size,
          fontface      = "bold",
          color         = "#1a3a6a",
          fill          = "#d8eef8",
          label.size    = 0.4,
          label.padding = unit(0.2, "lines"),
          lineheight    = 0.85
        )
    }
  }

  p
}

#' Save the board plot to a PNG file.
#'
#' @param board     A board list from \code{generate_board()}.
#' @param file      Output file path (default "board.png").
#' @param width     Width in inches (default 8).
#' @param height    Height in inches (default 8).
#' @param size      Hex size scalar passed to \code{plot_board()} (default 1).
save_board_plot <- function(board, file = "board.png",
                            width = 8, height = 8, size = 1) {
  p <- plot_board(board, size = size)
  ggsave(file, plot = p, width = width, height = height, dpi = 150)
  invisible(p)
}

# =============================================================================
# Player info panels
# =============================================================================

# Return "#FFFFFF" or "#1a1a1a" depending on which gives better contrast
# against the given hex background colour.
panel_text_color <- function(hex_color) {
  r <- strtoi(substr(hex_color, 2L, 3L), 16L) / 255
  g <- strtoi(substr(hex_color, 4L, 5L), 16L) / 255
  b <- strtoi(substr(hex_color, 6L, 7L), 16L) / 255
  if (0.299 * r + 0.587 * g + 0.114 * b > 0.5) "#1a1a1a" else "#FFFFFF"
}

# Build a compact VP breakdown string, e.g. "2S, 1C, LR, LA".
# S = settlement (1 VP each), C = city (2 VP each),
# LR = Longest Road (2 VP), LA = Largest Army (2 VP),
# VP* = hidden VP dev cards.
vp_detail_str <- function(player) {
  parts <- character(0)
  n_s <- length(player$settlement_locations)
  n_c <- length(player$city_locations)
  if (n_s > 0L)                   parts <- c(parts, sprintf("%dS", n_s))
  if (n_c > 0L)                   parts <- c(parts, sprintf("%dC", n_c))
  if (player$has_longest_road)    parts <- c(parts, "LR")
  if (player$has_largest_army)    parts <- c(parts, "LA")
  vp_cards <- player$dev_cards[["victory_point"]] +
              player$dev_cards_new[["victory_point"]]
  if (vp_cards > 0L)              parts <- c(parts, sprintf("%dVP*", vp_cards))
  if (length(parts) == 0L) return("(no VP yet)")
  paste(parts, collapse = ", ")
}

#' Build a single player info panel as a ggplot.
#'
#' Shows player identity, VP total with breakdown, special card status,
#' knights played, and current resources in hand.  The background colour
#' matches the player's piece colour from PLAYER_COLORS.
#'
#' @param player      A player list from \code{make_player()} / \code{run_game()}.
#' @param orientation "portrait" (tall side panel, default) or "landscape"
#'                    (short top panel with columns arranged horizontally).
#' @return A ggplot object suitable for composing with \code{patchwork}.
build_player_panel <- function(player, orientation = "portrait", size = 1) {
  pid     <- as.character(player$id)
  bg_col  <- unname(PLAYER_COLORS[pid])
  txt_col <- panel_text_color(bg_col)

  vp_total <- player$vp +
              player$dev_cards[["victory_point"]] +
              player$dev_cards_new[["victory_point"]]
  res <- player$resources

  # Base plot: blank coordinate space [0,1] x [0,1]
  p <- ggplot() +
    scale_x_continuous(limits = c(0, 1), expand = c(0, 0)) +
    scale_y_continuous(limits = c(0, 1), expand = c(0, 0)) +
    theme_void() +
    theme(
      plot.background = element_rect(fill = bg_col, color = "#333333",
                                     linewidth = 1.5),
      plot.margin     = margin(6 * size, 8 * size, 6 * size, 8 * size)
    )

  if (orientation == "landscape") {
    # ── Horizontal layout (top panel) ────────────────────────────────────────
    # Five columns: Identity | VP | Special cards | Knights | Resources
    col_x <- c(0.10, 0.29, 0.49, 0.665, 0.855)  # column centres
    div_x <- c(0.20, 0.38, 0.585, 0.745)          # vertical dividers

    for (xd in div_x) {
      p <- p + annotate("segment",
                        x = xd, xend = xd, y = 0.06, yend = 0.94,
                        color = txt_col, alpha = 0.25, linewidth = 0.4 * size)
    }

    # Gold column highlight when a special card is held
    if (player$has_longest_road || player$has_largest_army) {
      p <- p + annotate("rect",
                        xmin = div_x[2], xmax = div_x[3],
                        ymin = 0.0, ymax = 1.0,
                        fill = "#FFD700", alpha = 0.30, color = NA)
    }

    y1 <- 0.82   # primary row (labels / main values)
    y2 <- 0.35   # secondary row (details)

    lr_bold  <- player$has_longest_road
    la_bold  <- player$has_largest_army
    lr_alpha <- if (lr_bold) 1.0 else 0.45
    la_alpha <- if (la_bold) 1.0 else 0.45

    text_items <- list(
      # Col 1: Identity
      list(x = col_x[1], y = y1, txt = sprintf("Player %d", player$id),
           sz = 4.4 * size, bold = TRUE,  alpha = 1.0),
      list(x = col_x[1], y = y2, txt = player$strategy_name,
           sz = 3.3 * size, bold = FALSE, alpha = 1.0),
      # Col 2: VP
      list(x = col_x[2], y = y1, txt = sprintf("VP: %d", vp_total),
           sz = 4.0 * size, bold = TRUE,  alpha = 1.0),
      list(x = col_x[2], y = y2, txt = vp_detail_str(player),
           sz = 2.8 * size, bold = FALSE, alpha = 1.0),
      # Col 3: Special cards
      list(x = col_x[3], y = y1,
           txt   = sprintf("Longest Road: %s",
                           if (lr_bold) "\u2714" else "\u2014"),
           sz = 3.0 * size, bold = lr_bold, alpha = lr_alpha),
      list(x = col_x[3], y = y2,
           txt   = sprintf("Largest Army: %s",
                           if (la_bold) "\u2714" else "\u2014"),
           sz = 3.0 * size, bold = la_bold, alpha = la_alpha),
      # Col 4: Knights
      list(x = col_x[4], y = y1, txt = "Knights Played",
           sz = 3.0 * size, bold = TRUE,  alpha = 1.0),
      list(x = col_x[4], y = y2, txt = as.character(player$knights_played),
           sz = 4.0 * size, bold = FALSE, alpha = 1.0),
      # Col 5: Resources (header + 2 lines)
      list(x = col_x[5], y = y1, txt = "Resources",
           sz = 3.3 * size, bold = TRUE, alpha = 1.0),
      list(x = col_x[5], y = 0.58,
           txt = sprintf("L:%d  B:%d  W:%d",
                         res[["lumber"]], res[["brick"]], res[["wool"]]),
           sz = 2.8 * size, bold = FALSE, alpha = 1.0),
      list(x = col_x[5], y = 0.22,
           txt = sprintf("G:%d  O:%d", res[["grain"]], res[["ore"]]),
           sz = 2.8 * size, bold = FALSE, alpha = 1.0)
    )

    for (item in text_items) {
      p <- p + annotate(
        "text", x = item$x, y = item$y, label = item$txt,
        color    = txt_col,
        size     = item$sz,
        fontface = if (item$bold) "bold" else "plain",
        alpha    = item$alpha,
        hjust    = 0.5, vjust    = 1
      )
    }

  } else {
    # ── Portrait layout (side panels) ────────────────────────────────────────

    # Gold highlight bar behind held special cards
    if (player$has_longest_road) {
      p <- p + annotate("rect", xmin = 0.02, xmax = 0.98,
                        ymin = 0.510, ymax = 0.610,
                        fill = "#FFD700", alpha = 0.40, color = NA)
    }
    if (player$has_largest_army) {
      p <- p + annotate("rect", xmin = 0.02, xmax = 0.98,
                        ymin = 0.415, ymax = 0.515,
                        fill = "#FFD700", alpha = 0.40, color = NA)
    }

    # Section dividers
    for (div_y in c(0.785, 0.630, 0.370)) {
      p <- p + annotate("segment",
                        x = 0.05, xend = 0.95, y = div_y, yend = div_y,
                        color = txt_col, alpha = 0.30, linewidth = 0.4 * size)
    }

    text_rows <- list(
      list(y = 0.955, txt = sprintf("Player %d", player$id),
           sz = 4.4 * size, bold = TRUE,  alpha = 1.0),
      list(y = 0.855, txt = player$strategy_name,
           sz = 3.3 * size, bold = FALSE, alpha = 1.0),
      list(y = 0.750, txt = sprintf("VP: %d", vp_total),
           sz = 4.0 * size, bold = TRUE,  alpha = 1.0),
      list(y = 0.660, txt = vp_detail_str(player),
           sz = 2.8 * size, bold = FALSE, alpha = 1.0),
      list(y = 0.600,
           txt   = sprintf("Longest Road: %s",
                           if (player$has_longest_road) "\u2714" else "\u2014"),
           sz    = 3.0 * size,
           bold  = player$has_longest_road,
           alpha = if (player$has_longest_road) 1.0 else 0.45),
      list(y = 0.505,
           txt   = sprintf("Largest Army: %s",
                           if (player$has_largest_army) "\u2714" else "\u2014"),
           sz    = 3.0 * size,
           bold  = player$has_largest_army,
           alpha = if (player$has_largest_army) 1.0 else 0.45),
      list(y = 0.415, txt = sprintf("Knights Played: %d", player$knights_played),
           sz = 3.0 * size, bold = FALSE, alpha = 1.0),
      list(y = 0.345, txt = "Resources",
           sz = 3.3 * size, bold = TRUE,  alpha = 1.0),
      list(y = 0.230,
           txt = sprintf("L:%d  B:%d  W:%d",
                         res[["lumber"]], res[["brick"]], res[["wool"]]),
           sz = 2.8 * size, bold = FALSE, alpha = 1.0),
      list(y = 0.110,
           txt = sprintf("G:%d  O:%d", res[["grain"]], res[["ore"]]),
           sz = 2.8 * size, bold = FALSE, alpha = 1.0)
    )

    for (row in text_rows) {
      p <- p + annotate(
        "text", x = 0.5, y = row$y, label = row$txt,
        color    = txt_col,
        size     = row$sz,
        fontface = if (row$bold) "bold" else "plain",
        alpha    = row$alpha,
        hjust    = 0.5, vjust    = 1
      )
    }
  }

  p
}

#' Compose the full game-state view: board flanked by player info panels.
#'
#' Player 1 appears on the left, Player 2 across the top, Player 3 on the
#' right.  The board plot occupies the centre/bottom region.  Uses patchwork
#' for layout.
#'
#' @param board    A board list from \code{generate_board()}.
#' @param players  List of player objects from \code{run_game()$player_objects}.
#' @param size     Hex size scalar passed to \code{plot_board()} (default 1).
#' @return A patchwork object.
plot_game_state <- function(board, players, size = 1) {
  board_plt <- plot_board(board, size = size, players = players)

  panel_map <- setNames(
    lapply(players, function(pl) {
      ori <- if (as.character(pl$id) == "2") "landscape" else "portrait"
      build_player_panel(pl, orientation = ori, size = size)
    }),
    vapply(players, function(p) as.character(p$id), character(1))
  )

  p1 <- if ("1" %in% names(panel_map)) panel_map[["1"]] else plot_spacer()
  p2 <- if ("2" %in% names(panel_map)) panel_map[["2"]] else plot_spacer()
  p3 <- if ("3" %in% names(panel_map)) panel_map[["3"]] else plot_spacer()

  # Layout:  A = player 2 (top, full width)
  #          B = player 1 (left)   C = board (centre)   D = player 3 (right)
  # Column widths 2:4:2 → side panels are 1/4 each, board is 1/2.
  layout <- "
AAAAAAAA
BBCCCCDD
"
  (p2 + p1 + board_plt + p3) +
    plot_layout(design = layout, heights = c(1, 4))
}
