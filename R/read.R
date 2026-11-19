#' Read a file from SharePoint with any function
#'
#' Downloads one file to a temporary location, reads it with the function you
#' give, deletes the temporary copy, and returns whatever that function
#' returns. For Excel and CSV files, [less_read_excel()] and [less_read_csv()]
#' are easier: their options autocomplete and have help pages.
#'
#' @param x Where to look: a site, library or folder address copied from the
#'   browser, or a drive object from [less_drive()].
#' @param path The file, like a path on your computer: relative to wherever
#'   `x` points (`"tracker.xlsx"`, `"MPIP/tracker.xlsx"`), or from the top of
#'   the library if it starts with `/`. Any value from the `path` column of
#'   [less_contents()] works.
#' @param .f A function that reads a file, given its location as the first
#'   argument: e.g. `readxl::read_excel`, `readr::read_tsv`,
#'   `arrow::read_parquet`, or your own `\(file) ...`.
#' @param ... Passed on to `.f`.
#' @param library Which library, if `x` is a site with more than one. See
#'   [less_drive()]. Rarely needed.
#'
#' @return Whatever `.f` returns.
#' @export
#' @examples
#' \dontrun{
#' less_read(url, "MPIP/data.tsv", readr::read_tsv)
#' less_read(url, "MPIP/data.parquet", arrow::read_parquet)
#'
#' # A lambda, for anything that doesn't take the file first
#' less_read(url, "notes.docx", \(file) officer::read_docx(path = file))
#' }
less_read <- function(x, path, .f, ..., library = NULL) {
  # Name the reader for error messages before anything evaluates `.f`.
  reader <- if (missing(.f)) "" else rlang::as_label(rlang::enexpr(.f))
  less_check_file_path(if (missing(path)) NULL else path)
  if (missing(.f) || !is.function(.f)) {
    cli::cli_abort(c(
      "{.arg .f} must be a function that reads a file, like {.code readxl::read_excel}.",
      "i" = "For Excel or CSV files, {.fn less_read_excel} and {.fn less_read_csv} need no {.arg .f}."
    ))
  }

  place <- less_locate(x, library)
  file <- less_resolve_path(path, place$base)
  temp <- less_download(place$drive, file, hint = less_path_hint(path, place$base))
  on.exit(if (fs::file_exists(temp)) fs::file_delete(temp), add = TRUE)

  tryCatch(
    .f(temp, ...),
    error = function(e) {
      cli::cli_abort(
        "Downloaded {.val {stringr::str_c('/', file)}}, but {.code {reader}} couldn't read it.",
        parent = e, call = NULL
      )
    }
  )
}

#' Read an Excel file from SharePoint
#'
#' A shortcut for `less_read(x, path, readxl::read_excel, ...)`. The options
#' are [readxl::read_excel()]'s, with the same names and defaults.
#'
#' @inheritParams less_read
#' @inheritParams readxl::read_excel
#' @param path The file, e.g. `"tracker.xlsx"`. Relative to wherever `x`
#'   points, or from the top of the library if it starts with `/`. Any value
#'   from the `path` column of [less_contents()] works.
#' @param ... Other options passed on to [readxl::read_excel()].
#'
#' @return A tibble.
#' @export
#' @examples
#' \dontrun{
#' less_read_excel(url, "MPIP/tracker.xlsx")
#' less_read_excel(url, "MPIP/tracker.xlsx", sheet = "Summary", skip = 2)
#' }
less_read_excel <- function(x, path, sheet = NULL, range = NULL, col_names = TRUE,
                            col_types = NULL, na = "", skip = 0, n_max = Inf, ...,
                            library = NULL) {
  less_read(
    x, path, readxl::read_excel,
    sheet = sheet, range = range, col_names = col_names, col_types = col_types,
    na = na, skip = skip, n_max = n_max, ...,
    library = library
  )
}

#' Read a CSV file from SharePoint
#'
#' A shortcut for `less_read(x, path, readr::read_csv, ...)`. The options are
#' [readr::read_csv()]'s, with the same names and defaults.
#'
#' @inheritParams less_read
#' @inheritParams readr::read_csv
#' @param path The file, e.g. `"extract.csv"`. Relative to wherever `x`
#'   points, or from the top of the library if it starts with `/`. Any value
#'   from the `path` column of [less_contents()] works.
#' @param ... Other options passed on to [readr::read_csv()].
#'
#' @return A tibble.
#' @export
#' @examples
#' \dontrun{
#' less_read_csv(url, "MPIP/extract.csv")
#' less_read_csv(url, "MPIP/extract.csv", col_types = "ccd", skip = 1)
#' }
less_read_csv <- function(x, path, col_names = TRUE, col_types = NULL,
                          na = c("", "NA"), skip = 0, n_max = Inf, ...,
                          library = NULL) {
  less_read(
    x, path, readr::read_csv,
    col_names = col_names, col_types = col_types, na = na, skip = skip,
    n_max = n_max, ...,
    library = library
  )
}

# Download one file to a temporary path that keeps its extension (read_excel()
# tells .xls from .xlsx by it). Returns the temporary path.
less_download <- function(drive, file, hint = NULL) {
  temp <- fs::file_temp(ext = fs::path_ext(file))
  tryCatch(
    drive$download_file(src = file, dest = temp, overwrite = TRUE),
    error = function(e) {
      cli::cli_abort(c(
        "Couldn't download {.val {stringr::str_c('/', file)}}{less_in_library(drive)}.",
        "x" = conditionMessage(e),
        "i" = "{hint}"
      ), call = NULL)
    }
  )
  temp
}

less_check_file_path <- function(path, call = rlang::caller_env()) {
  if (!rlang::is_string(path) || stringr::str_remove_all(path, "/") == "") {
    cli::cli_abort(
      "{.arg path} must be the file to read, like {.val tracker.xlsx} or {.val MPIP/tracker.xlsx}.",
      call = call
    )
  }
}
