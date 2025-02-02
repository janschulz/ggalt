#' Similar to \code{coord_map} but uses the PROJ.4 library/package for projection
#' transformation
#'
#' The representation of a portion of the earth, which is approximately
#' spherical, onto a flat 2D plane requires a projection. This is what
#' \code{coord_proj} does, using the \code{proj4::project()} function from
#' the \code{proj4} package.
#'
#' \if{html}{
#' A sample of the output from \code{coord_proj()} using the Winkel-Tripel projection:
#'
#' \figure{coord_proj_01.png}{options: width="100\%" alt="Figure: coord_proj_01.png"}
#' }
#'
#' \if{latex}{
#' A sample of the output from \code{coord_proj()} using the Winkel-Tripel projection:
#'
#' \figure{coordproj01.pdf}{options: width=10cm}
#' }
#'
#' @param proj projection definition. If left \code{NULL} will default to
#'        a Robinson projection
#' @param inverse	if \code{TRUE} inverse projection is performed (from a
#'        cartographic projection into lat/long), otherwise projects from
#'        lat/long into a cartographic projection.
#' @param degrees	if \code{TRUE} then the lat/long data is assumed to be in
#'        degrees, otherwise in radians
#' @param ellps.default	default ellipsoid that will be added if no datum or
#'        ellipsoid parameter is specified in proj. Older versions of PROJ.4
#'        didn't require a datum (and used sphere by default), but 4.5.0 and
#'        higher always require a datum or an ellipsoid. Set to  \code{NA} if no
#'        datum should be added to proj (e.g. if you specify an ellipsoid
#'        directly).
#' @param xlim manually specify x limits (in degrees of longitude)
#' @param ylim manually specify y limits (in degrees of latitude)
#' @note When \code{inverse} is \code{FALSE} \code{coord_proj} makes a fairly
#'       large assumption that the coordinates being transformed are within
#'       -180:180 (longitude) and -90:90 (latitude). As such, it truncates
#'       all longitude & latitude input to fit within these ranges. More updates
#'       to this new \code{coord_} are planned.
#' @export
#' @examples
#' # World in Winkel-Tripel
#' world <- map_data("world")
#' world <- world[world$region != "Antarctica",]
#'
#' gg <- ggplot()
#' gg <- gg + geom_map(data=world, map=world,
#'                     aes(x=long, y=lat, map_id=region))
#' gg <- gg + coord_proj("+proj=wintri")
#' gg
#'
#' # U.S.A. Albers-style
#' usa <- world[world$region == "USA",]
#' usa <- usa[!(usa$subregion %in% c("Alaska", "Hawaii")),]
#'
#' gg <- ggplot()
#' gg <- gg + geom_map(data=usa, map=usa,
#'                     aes(x=long, y=lat, map_id=region))
#' gg <- gg + coord_proj(
#'              paste0("+proj=aea +lat_1=29.5 +lat_2=45.5 +lat_0=37.5 +lon_0=-96",
#'                     " +x_0=0 +y_0=0 +ellps=GRS80 +datum=NAD83 +units=m +no_defs"))
#' gg
#'
#' # Showcase Greenland (properly)
#' greenland <- world[world$region == "Greenland",]
#'
#' gg <- ggplot()
#' gg <- gg + geom_map(data=greenland, map=greenland,
#'                     aes(x=long, y=lat, map_id=region))
#' gg <- gg + coord_proj(
#'              paste0("+proj=stere +lat_0=90 +lat_ts=70 +lon_0=-45 +k=1 +x_0=0",
#'                     " +y_0=0 +ellps=WGS84 +datum=WGS84 +units=m +no_defs"))
#' gg
coord_proj <- function(proj=NULL, inverse = FALSE, degrees = TRUE,
                       ellps.default="sphere", xlim = NULL, ylim = NULL) {

  if (is.null(proj)) {
    proj <- paste0(c("+proj=robin +lon_0=0 +x_0=0 +y_0=0",
                     "+ellps=WGS84 +datum=WGS84 +units=m +no_defs"),
                   collapse=" ")
  }

  ggproto(NULL, CoordProj,
    proj = proj,
    inverse = inverse,
    ellps.default = ellps.default,
    degrees = degrees,
    limits = list(x = xlim, y = ylim),
    params= list()
  )

}

#' Geom Proto
#' @rdname ggalt-ggproto
#' @format NULL
#' @usage NULL
#' @keywords internal
#' @export
CoordProj <- ggproto("CoordProj", Coord,

  transform = function(self, data, scale_details) {

    trans <- project4(self, data$x, data$y)
    out <- cunion(trans[c("x", "y")], data)

    out$x <- rescale(out$x, 0:1, scale_details$x.proj)
    out$y <- rescale(out$y, 0:1, scale_details$y.proj)
    out

  },

  distance = function(x, y, scale_details) {
    max_dist <- dist_central_angle(scale_details$x.range, scale_details$y.range)
    dist_central_angle(x, y) / max_dist
  },

  aspect = function(ranges) {
    diff(ranges$y.proj) / diff(ranges$x.proj)
  },

  train = function(self, scale_details) {

    # range in scale
    ranges <- list()
    for (n in c("x", "y")) {

      scale <- scale_details[[n]]
      limits <- self$limits[[n]]

      if (is.null(limits)) {
        range <- scale$dimension(expand_default(scale))
      } else {
        range <- range(scale$transform(limits))
      }
      ranges[[n]] <- range
    }

    orientation <- self$orientation %||% c(90, 0, mean(ranges$x))

    # Increase chances of creating valid boundary region
    grid <- expand.grid(
      x = seq(ranges$x[1], ranges$x[2], length.out = 50),
      y = seq(ranges$y[1], ranges$y[2], length.out = 50)
    )

    ret <- list(x = list(), y = list())

    # range in map
    proj <- project4(self, grid$x, grid$y)$range
    ret$x$proj <- proj[1:2]
    ret$y$proj <- proj[3:4]

    for (n in c("x", "y")) {
      out <- scale_details[[n]]$break_info(ranges[[n]])
      ret[[n]]$range <- out$range
      ret[[n]]$major <- out$major_source
      ret[[n]]$minor <- out$minor_source
      ret[[n]]$labels <- out$labels
    }

    details <- list(
      orientation = orientation,
      x.range = ret$x$range, y.range = ret$y$range,
      x.proj = ret$x$proj, y.proj = ret$y$proj,
      x.major = ret$x$major, x.minor = ret$x$minor, x.labels = ret$x$labels,
      y.major = ret$y$major, y.minor = ret$y$minor, y.labels = ret$y$labels
    )
    details
  },

  render_bg = function(self, scale_details, theme) {
    xrange <- expand_range(scale_details$x.range, 0.2)
    yrange <- expand_range(scale_details$y.range, 0.2)

    # Limit ranges so that lines don't wrap around globe
    xmid <- mean(xrange)
    ymid <- mean(yrange)
    xrange[xrange < xmid - 180] <- xmid - 180
    xrange[xrange > xmid + 180] <- xmid + 180
    yrange[yrange < ymid - 90] <- ymid - 90
    yrange[yrange > ymid + 90] <- ymid + 90

    xgrid <- with(scale_details, expand.grid(
      y = c(seq(yrange[1], yrange[2], length.out = 50), NA),
      x = x.major
    ))
    ygrid <- with(scale_details, expand.grid(
      x = c(seq(xrange[1], xrange[2], length.out = 50), NA),
      y = y.major
    ))

    xlines <- self$transform(xgrid, scale_details)
    ylines <- self$transform(ygrid, scale_details)

    if (nrow(xlines) > 0) {
      grob.xlines <- element_render(
        theme, "panel.grid.major.x",
        xlines$x, xlines$y, default.units = "native"
      )
    } else {
      grob.xlines <- zeroGrob()
    }

    if (nrow(ylines) > 0) {
      grob.ylines <- element_render(
        theme, "panel.grid.major.y",
        ylines$x, ylines$y, default.units = "native"
      )
    } else {
      grob.ylines <- zeroGrob()
    }

    ggname("grill", grobTree(
      element_render(theme, "panel.background"),
      grob.xlines, grob.ylines
    ))
  },

  render_axis_h = function(self, scale_details, theme) {
    if (is.null(scale_details$x.major)) return(zeroGrob())

    x_intercept <- with(scale_details, data.frame(
      x = x.major,
      y = y.range[1]
    ))
    pos <- self$transform(x_intercept, scale_details)

    guide_axis(pos$x, scale_details$x.labels, "bottom", theme)
  },

  render_axis_v = function(self, scale_details, theme) {
    if (is.null(scale_details$y.major)) return(zeroGrob())

    x_intercept <- with(scale_details, data.frame(
      x = x.range[1],
      y = y.major
    ))
    pos <- self$transform(x_intercept, scale_details)

    guide_axis(pos$y, scale_details$y.labels, "left", theme)
  }

)


project4 <- function(coord, x, y) {

  df <- data.frame(x=x, y=y)

  if (!coord$inverse) {

    # map extremes cause issues with projections both with proj4 &
    # spTransform. this compensates for them.

    df$x <- ifelse(df$x <= -180, -179.99999999999, df$x)
    df$x <- ifelse(df$x >= 180, 179.99999999999, df$x)
    df$y <- ifelse(df$y <= -90, -89.99999999999, df$y)
    df$y <- ifelse(df$y >= 90, 89.99999999999, df$y)

  }

  suppressWarnings({
    res <- proj4::project(list(x=df$x, y=df$y),
                          proj = coord$proj,
                          inverse = coord$inverse,
                          degrees  = coord$degrees,
                          ellps.default = coord$ellps.default)
    res$range <- c(range(res$x, na.rm=TRUE), range(res$y, na.rm=TRUE))
    res$error <- 0
    res
  })
}

