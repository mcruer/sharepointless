#' List the contents of a SharePoint document library
#'
#' Lists the files and folders in a document library (or one folder of it) as
#' a tibble, one row per item, with times parsed and people's names pulled out
#' of Microsoft's nested metadata. Set `max_depth` to include subfolders too.
#'
#' @param x Where to look. Any of:
#'   * a library or folder address copied from the browser (containing
#'     `/Forms/AllItems.aspx`). A folder address starts the listing in that
#'     folder.
#'   * a site address (the site's default library is used; see `library`).
#'   * a drive object from [less_drive()].
#' @param path Folder to list, like a path on your computer:
#'   * `NULL` (the default): wherever `x` points.
#'   * `"MPIP"` or `"Budget/2025"`: relative to wherever `x` points.
#'   * `"/Budget"`: starting with `/` means from the top of the library,
#'     whatever `x` points to. `"/"` is the library itself.
#'
#'   Any value from the `path` column of an earlier result works here.
#' @param max_depth How many levels of subfolders to go into. `0` (the
#'   default) lists just the starting folder; `1` adds the contents of its
#'   subfolders; `Inf` lists everything below it. Each folder is a separate
#'   request to Microsoft, so `Inf` on a big library takes a while.
#' @param library Which library, if `x` is a site with more than one and you
#'   don't want the default. See [less_drive()]. Rarely needed: a library or
#'   folder address already says which library.
#'
#' @return A tibble with one row per file or folder, in folder order:
#'   * `name`: the file or folder name
#'   * `is_folder`: `TRUE` for folders
#'   * `size`: an [fs::fs_bytes()] number, printed as e.g. `1.05G`. For a
#'     folder, the total size of everything in it. Sorts, filters and sums
#'     like any number.
#'   * `modified`, `created`: date-times (POSIXct), in your computer's time zone
#'   * `modified_by`, `created_by`: people's display names (or an app's name,
#'     e.g. a Power Automate flow, when no person was involved)
#'   * `depth`: `0` for items in the starting folder, `1` one level down, and so on
#'   * `path`: the item's full path in the library, starting with `/`, e.g.
#'     `"/Budget/2025/plan.xlsx"`. Feed it back to `path` to go there.
#'   * `web_url`: the item's address, to open it in a browser
#'   * `id`: the item's ID, which stays the same if it's renamed or moved
#' @export
#' @examples
#' \dontrun{
#' url <- "https://contoso.sharepoint.com/sites/Team/Shared%20Documents/Forms/AllItems.aspx"
#'
#' less_contents(url)                         # top of the library
#' less_contents(url, "Budget")               # a folder in it
#' less_contents(url, "Budget", max_depth = Inf)   # and everything below
#'
#' # With a folder address, paths are relative to that folder...
#' less_contents(url_folder, "2025")
#' # ...and a leading / goes back to the top of the library
#' less_contents(url_folder, "/")
#'
#' # Go into a folder from an earlier result
#' contents <- less_contents(url)
#' less_contents(url, contents$path[1])
#' }
less_contents <- function(x, path = NULL, max_depth = 0, library = NULL) {
  if (!is.numeric(max_depth) || length(max_depth) != 1 || is.na(max_depth) || max_depth < 0) {
    cli::cli_abort("{.arg max_depth} must be a single number, 0 or more (use {.code Inf} for everything).")
  }
  if (!is.null(path) && !rlang::is_string(path)) {
    cli::cli_abort("{.arg path} must be a single folder path, like {.val Budget/2025}.")
  }

  place <- less_locate(x, library)
  start <- less_resolve_path(path, place$base)
  hint <- less_path_hint(path, place$base)

  less_contents_walk(place$drive, start, depth = 0, max_depth = max_depth, hint = hint) |>
    dplyr::arrange(.data$path)
}

# One folder, then (if allowed) each subfolder, depth-first.
less_contents_walk <- function(drive, folder, depth, max_depth, hint = NULL) {
  items <- drive |>
    less_list_raw(folder, hint) |>
    less_tidy_items(folder, depth)

  if (depth >= max_depth) {
    return(items)
  }

  children <- items |>
    dplyr::filter(.data$is_folder) |>
    dplyr::pull(.data$path) |>
    stringr::str_remove("^/") |>
    purrr::map(\(p) less_contents_walk(drive, p, depth + 1, max_depth, hint))

  dplyr::bind_rows(items, children)
}

less_list_raw <- function(drive, folder, hint = NULL) {
  tryCatch(
    drive$list_files(if (folder == "") "/" else folder, info = "all"),
    error = function(e) {
      where <- less_in_library(drive)
      cli::cli_abort(c(
        "Couldn't list the folder {.val {stringr::str_c('/', folder)}}{where}.",
        "x" = conditionMessage(e),
        "i" = "{hint}"
      ), call = NULL)
    }
  )
}

# Flatten Microsoft365R's list_files(info = "all") data frame. Its people and
# file details arrive as nested data-frame columns (createdBy$user$displayName),
# and not every column appears in every folder, so dig for each field and fall
# back to NA rather than assuming it's there.
less_tidy_items <- function(raw, folder, depth) {
  if (NROW(raw) == 0) {
    return(less_contents_template())
  }

  name <- as.character(raw$name)

  tibble::tibble(
    name        = name,
    is_folder   = as.logical(raw$isdir),
    size        = fs::as_fs_bytes(as.numeric(raw$size)),
    modified    = less_parse_time(less_dig(raw, "lastModifiedDateTime")),
    modified_by = less_who(raw, "lastModifiedBy"),
    created     = less_parse_time(less_dig(raw, "createdDateTime")),
    created_by  = less_who(raw, "createdBy"),
    depth       = depth,
    path        = if (folder == "") stringr::str_c("/", name) else stringr::str_c("/", folder, "/", name),
    web_url     = less_dig(raw, "webUrl"),
    id          = less_dig(raw, "id")
  )
}

less_contents_template <- function() {
  tibble::tibble(
    name = character(), is_folder = logical(), size = fs::fs_bytes(),
    modified = as.POSIXct(character(), tz = ""), modified_by = character(),
    created = as.POSIXct(character(), tz = ""), created_by = character(),
    depth = numeric(), path = character(),
    web_url = character(), id = character()
  )
}

# A person's display name, or the app's (e.g. a Power Automate flow) when no
# person was involved.
less_who <- function(raw, field) {
  dplyr::coalesce(
    less_dig(raw, field, "user", "displayName"),
    less_dig(raw, field, "application", "displayName")
  )
}

less_dig <- function(raw, ...) {
  value <- purrr::pluck(raw, ...)
  if (is.null(value)) rep(NA_character_, NROW(raw)) else as.character(value)
}

# Graph returns ISO 8601 in UTC ("2024-12-10T13:51:07Z"); show local time.
less_parse_time <- function(x) {
  x |>
    lubridate::ymd_hms(quiet = TRUE) |>
    lubridate::with_tz(tzone = "")
}
