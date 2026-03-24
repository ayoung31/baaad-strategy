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
  forest   = "Forest (Lumber)",
  hills    = "Hills (Brick)",
  pasture  = "Pasture (Wool)",
  fields   = "Fields (Grain)",
  mountain = "Mountain (Ore)",
  desert   = "Desert"
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
      lx    = mx + mx / d * 1.1 * size,   # label: pushed outward
      ly    = my + my / d * 1.1 * size,
      x1    = pa["x"], y1 = pa["y"],       # intersection A on boundary
      x2    = pb["x"], y2 = pb["y"],       # intersection B on boundary
      stringsAsFactors = FALSE
    )
  }
  if (length(rows) == 0) return(NULL)
  do.call(rbind, rows)
}

# -----------------------------------------------------------------------------
# Main plotting function
# -----------------------------------------------------------------------------

#' Plot a Catan board.
#'
#' @param board  A board list from \code{generate_board()}.
#' @param size   Hex size scalar (default 1). Increase for a larger plot.
#' @param ports  Logical; if TRUE, annotate port positions (default TRUE).
#' @return A ggplot object.
plot_board <- function(board, size = 1, ports = TRUE) {
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
      name   = NULL,
      guide  = guide_legend(override.aes = list(color = NA))
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

    coord_equal() +
    theme_void(base_size = 11) +
    theme(
      plot.title        = element_text(hjust = 0.5, face = "bold", size = 13),
      plot.background   = element_rect(fill = "#d0eaf8", color = NA),
      legend.position   = "right",
      legend.key.size   = unit(0.9, "lines"),
      legend.text       = element_text(size = 9),
      plot.margin       = margin(10, 10, 10, 10)
    ) +
    labs(title = "Catan Board")

  # Port indicators: dashed lines to both intersections + endpoint dots + label
  if (ports) {
    port_df <- tryCatch(build_port_df(board, size), error = function(e) NULL)
    if (!is.null(port_df) && nrow(port_df) > 0) {
      p <- p +
        geom_segment(
          data = port_df,
          aes(x = lx, y = ly, xend = x1, yend = y1),
          color = "#1a3a6a", linewidth = 0.4, linetype = "dashed"
        ) +
        geom_segment(
          data = port_df,
          aes(x = lx, y = ly, xend = x2, yend = y2),
          color = "#1a3a6a", linewidth = 0.4, linetype = "dashed"
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
          size          = 2.2 * size,
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
