#' Create a data table tbl.
#'
#' A data table tbl wraps a local data table.
#'
#' @export
#' @param data a data table
#' @param copy If the input is a data.table, copy it?
#' @aliases .datatable.aware
#' @examples
#' ds <- tbl_dt(mtcars)
#' ds
#' data.table::as.data.table(ds)
#'
#' library(dplyr, warn.conflicts = FALSE)
#' if (require("nycflights13")) {
#' flights2 <- tbl_dt(flights)
#' flights2 %>% filter(month == 1, day == 1, dest == "DFW")
#' flights2 %>% select(year:day)
#' flights2 %>% rename(Year = year)
#' flights2 %>%
#'   summarise(
#'     delay = mean(arr_delay, na.rm = TRUE),
#'     n = length(arr_delay)
#'   )
#' flights2 %>%
#'   mutate(gained = arr_delay - dep_delay) %>%
#'   select(ends_with("delay"), gained)
#' flights2 %>%
#'   arrange(dest, desc(arr_delay))
#'
#' by_dest <- group_by(flights2, dest)
#'
#' filter(by_dest, arr_delay == max(arr_delay, na.rm = TRUE))
#' summarise(by_dest, arr = mean(arr_delay, na.rm = TRUE))
#'
#' # Normalise arrival and departure delays by airport
#' by_dest %>%
#'   mutate(arr_z = scale(arr_delay), dep_z = scale(dep_delay)) %>%
#'   select(starts_with("arr"), starts_with("dep"))
#'
#' arrange(by_dest, desc(arr_delay))
#' select(by_dest, -(day:tailnum))
#' rename(by_dest, Year = year)
#'
#' # All manip functions preserve grouping structure, except for summarise
#' # which removes a grouping level
#' by_day <- group_by(flights2, year, month, day)
#' by_month <- summarise(by_day, delayed = sum(arr_delay > 0, na.rm = TRUE))
#' by_month
#' summarise(by_month, delayed = sum(delayed))
#'
#' # You can also manually ungroup:
#' ungroup(by_day)
#' }
tbl_dt <- function(data, copy = TRUE) {
  if (is.grouped_dt(data)) return(ungroup(data))

  if (data.table::is.data.table(data)) {
    if (copy)
      data <- data.table::copy(data)
  } else {
    data <- data.table::as.data.table(data)
  }
  data.table::setattr(data, "class", c("tbl_dt", "tbl", "data.table", "data.frame"))
  data
}

#' @export
#' @importFrom dplyr as.tbl
as.tbl.data.table <- function(x, ...) {
  tbl_dt(x)
}

#' @importFrom dplyr tbl_vars
#' @export
tbl_vars.tbl_dt <- function(x) data.table::copy(names(x))

#' @importFrom dplyr groups
#' @export
groups.tbl_dt <- function(x) {
  NULL
}

#' @importFrom dplyr ungroup
#' @export
ungroup.tbl_dt <- function(x, ...) x

#' @export
ungroup.data.table <- function(x, ...) x

#' @importFrom dplyr same_src
#' @export
same_src.tbl_dt <- function(x, y) {
  data.table::is.data.table(y)
}

#' @importFrom dplyr auto_copy
#' @export
auto_copy.tbl_dt <- function(x, y, copy = FALSE, ...) {
  data.table::as.data.table(as.data.frame(y))
}

# Standard data frame methods --------------------------------------------------

#' @export
as.data.frame.tbl_dt <- function(x, row.names = NULL, optional = FALSE, ...) {
  NextMethod()
}

#' @export
print.tbl_dt <- function(x, ..., n = NULL, width = NULL) {
  cat("Source: local data table ", dplyr::dim_desc(x), "\n", sep = "")
  cat("\n")
  print(dplyr::trunc_mat(x, n = n, width = width))

  invisible(x)
}

#' @export
dimnames.tbl_dt <- function(x) data.table::copy(NextMethod())

#' @importFrom utils head
#' @export
head.tbl_dt <- function(x, ...) tbl_dt(NextMethod())

#' @importFrom utils tail
#' @export
tail.tbl_dt <- function(x, ...) tbl_dt(NextMethod())

#' @export
#' @method all.equal tbl_dt
all.equal.tbl_dt <- function(target, current, ignore_col_order = TRUE,
                             ignore_row_order = TRUE, convert = FALSE, ...) {
  dplyr::all_equal(target, current, ignore_col_order = ignore_col_order,
    ignore_row_order = ignore_row_order, convert = convert, ...)
}

#' @export
.datatable.aware <- TRUE

# Filter -----------------------------------------------------------------------

and_expr <- function(exprs) {
  stopifnot(is.list(exprs))
  if (length(exprs) == 0) return(TRUE)
  if (length(exprs) == 1) return(exprs[[1]])

  left <- exprs[[1]]
  for (i in 2:length(exprs)) {
    left <- substitute(left & right, list(left = left, right = exprs[[i]]))
  }
  left
}

# The S3 method is registered manually in .onLoad() to avoid an R CMD
# check warning

filter.data.table <- function(.data, ...) {
  filter_(.data, .dots = lazyeval::lazy_dots(...))
}

#' @importFrom dplyr filter_
filter_.grouped_dt <- function(.data, ..., .dots) {
  grouped_dt(NextMethod(), groups(.data), copy = FALSE)
}
filter_.tbl_dt <- function(.data, ..., .dots) {
  tbl_dt(NextMethod(), copy = FALSE)
}
filter_.data.table <- function(.data, ..., .dots) {
  dots <- lazyeval::all_dots(.dots, ...)
  env <- lazyeval::common_env(dots)

  # http://stackoverflow.com/questions/16573995/subset-by-group-with-data-table
  expr <- lapply(dots, `[[`, "expr")
  j <- substitute(list(`_row` = .I[expr]), list(expr = and_expr(expr)))
  indices <- dt_subset(.data, , j, env)$`_row`

  .data[indices[!is.na(indices)]]
}

# Summarise --------------------------------------------------------------------

summarise.data.table <- function(.data, ...) {
  summarise_(.data, .dots = lazyeval::lazy_dots(...))
}

#' @importFrom dplyr summarise_
summarise_.grouped_dt <- function(.data, ..., .dots) {
  grouped_dt(NextMethod(), drop_last(groups(.data)), copy = FALSE)
}
summarise_.tbl_dt <- function(.data, ..., .dots) {
  tbl_dt(NextMethod(), copy = FALSE)
}
summarise_.data.table <- function(.data, ..., .dots) {
  dots <- lazyeval::all_dots(.dots, ..., all_named = TRUE)

  j <- lazyeval::make_call(quote(list), dots)
  dt_subset(.data, , j$expr, env = j$env)
}

# Mutate -----------------------------------------------------------------------

mutate.data.table <- function(.data, ...) {
  mutate_(.data, .dots = lazyeval::lazy_dots(...))
}

#' @importFrom dplyr mutate_
mutate_.grouped_dt <- function(.data, ..., .dots) {
  grouped_dt(NextMethod(), drop_last(groups(.data)), copy = FALSE)
}
mutate_.tbl_dt <- function(.data, ..., .dots) {
  tbl_dt(NextMethod(), copy = FALSE)
}
mutate_.data.table <- function(.data, ..., .dots) {
  dots <- lazyeval::all_dots(.dots, ..., all_named = TRUE)
  names <- lapply(names(dots), as.name)

  # Never want to modify in place
  .data <- data.table::copy(.data)

  for(i in seq_along(dots)) {
    # For each new variable, generate a call of the form df[, new := expr]
    j <- substitute(lhs := rhs, list(lhs = names[[i]], rhs = dots[[i]]$expr))
    .data <- dt_subset(.data, , j, dots[[i]]$env)
  }

  # Need to use this syntax to make the output visible (#11).
  .data[]
}

# Arrange ----------------------------------------------------------------------

arrange.data.table <- function(.data, ...) {
  arrange_(.data, .dots = lazyeval::lazy_dots(...))
}

#' @importFrom dplyr arrange_
arrange_.grouped_dt <- function(.data, ..., .dots) {
  grouped_dt(NextMethod(), groups(.data), copy = FALSE)
}
arrange_.tbl_dt <- function(.data, ..., .dots) {
  tbl_dt(NextMethod(), copy = FALSE)
}
arrange_.data.table <- function(.data, ..., .dots) {
  dots <- lazyeval::all_dots(.dots, ...)

  groups <- lazyeval::as.lazy_dots(groups(.data),
    env = lazyeval::common_env(dots))
  i <- lazyeval::make_call(quote(order), c(groups, dots))

  dt_subset(.data, i$expr, , env = i$env)
}

# Select -----------------------------------------------------------------------

select.data.table <- function(.data, ...) {
  select_(.data, .dots = lazyeval::lazy_dots(...))
}

#' @importFrom dplyr select_
select_.grouped_dt <- function(.data, ..., .dots) {
  dots <- lazyeval::all_dots(.dots, ...)
  vars <- dplyr::select_vars_(names(.data), dots,
    include = as.character(groups(.data)))
  out <- .data[, vars, drop = FALSE, with = FALSE]
  data.table::setnames(out, names(vars))

  grouped_dt(out, groups(.data), copy = FALSE)
}
select_.data.table <- function(.data, ..., .dots) {
  dots <- lazyeval::all_dots(.dots, ...)
  vars <- dplyr::select_vars_(names(.data), dots)

  out <- .data[, vars, drop = FALSE, with = FALSE]
  data.table::setnames(out, names(vars))
  out
}
select_.tbl_dt <- function(.data, ..., .dots) {
  tbl_dt(NextMethod(), copy = FALSE)
}

# Rename -----------------------------------------------------------------------

rename.data.table <- function(.data, ...) {
  rename_(.data, .dots = lazyeval::lazy_dots(...))
}

#' @importFrom dplyr rename_
rename_.grouped_dt <- function(.data, ..., .dots) {
  dots <- lazyeval::all_dots(.dots, ...)
  vars <- dplyr::rename_vars_(names(.data), dots)

  out <- .data[, vars, drop = FALSE, with = FALSE]
  data.table::setnames(out, names(vars))

  grouped_dt(out, groups(.data), copy = FALSE)
}
rename_.data.table <- function(.data, ..., .dots) {
  dots <- lazyeval::all_dots(.dots, ...)
  vars <- dplyr::rename_vars_(names(.data), dots)

  out <- .data[, vars, drop = FALSE, with = FALSE]
  data.table::setnames(out, names(vars))
  out
}
rename_.tbl_dt <- function(.data, ..., .dots) {
  tbl_dt(NextMethod(), copy = FALSE)
}


# Slice -------------------------------------------------------------------

slice.data.table <- function(.data, ...) {
  slice_(.data, .dots = lazyeval::lazy_dots(...))
}

#' @importFrom dplyr slice_
slice_.grouped_dt <- function(.data, ..., .dots) {
  grouped_dt(NextMethod(), groups(.data), copy = FALSE)
}
slice_.tbl_dt <- function(.data, ..., .dots) {
  tbl_dt(NextMethod(), copy = FALSE)
}
slice_.data.table <- function(.data, ..., .dots) {
  dots <- lazyeval::all_dots(.dots, ..., all_named = TRUE)
  env <- lazyeval::common_env(dots)

  j <- substitute(.SD[rows], list(rows = dots[[1]]$expr))
  dt_subset(.data, , j, env)
}
