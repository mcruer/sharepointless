#' List the contents of a SharePoint document library
#'
#' Lists the files and folders in a document library (or one folder of it) as
#' a tibble, one row per item, with times parsed and people's names pulled out
#' of Microsoft's nested metadata. Set `max_depth` to include subfolders too.
#'
#' @param x Where to look. Any of:
#'   * a library address copied from the browser (ending `/Forms/AllItems.aspx`).
#'     If you'd clicked into a folder, the listing starts in that folder.
#'   * a site address, plus `library` to say which library.
#'   * a drive object from [less_drive()].
#' @param library Which library, if `x` is a site address. See [less_drive()].
#' @param path Folder to start in, relative to the library root, e.g.
#'   `"Budget/2025"`. Overrides any folder in `x`. Leave `NULL` to start at
#'   the root (or the folder in `x`).
#' @param max_depth How many levels of subfolders to go into. `0` (the
#'   default) lists just the starting folder; `1` adds the contents of its
#'   subfolders; `Inf` lists everything below it. Each folder is a separate
#'   request to Microsoft, so `Inf` on a big library takes a while.
#'
#' @return A tibble with one row per file or folder:
#'   * `path`: the item's path from the library root, e.g. `"Budget/2025/plan.xlsx"`
#'   * `name`: the file or folder name
#'   * `is_folder`: `TRUE` for folders
#'   * `depth`: `0` for items in the starting folder, `1` one level down, and so on
#'   * `size`: in bytes. For a folder, the total size of everything in it.
#'   * `created`, `modified`: date-times (POSIXct), in your computer's time zone
#'   * `created_by`, `modified_by`: people's display names (or an app's name,
#'     e.g. a Power Automate flow, when no person was involved)
#'   * `web_url`: the item's address, to open it in a browser
#'   * `id`: the item's ID, which stays the same if it's renamed or moved
#' @export
#' @examples
#' \dontrun{
#' # Top level of a library, straight from the browser
#' less_contents("https://contoso.sharepoint.com/sites/Team/Shared%20Documents/Forms/AllItems.aspx")
#'
#' # Everything in one folder and below
#' less_contents("https://contoso.sharepoint.com/sites/Team",
#'               library = "^Documents$", path = "Budget", max_depth = Inf)
#'
#' # Reuse a drive object
#' drive <- less_drive("https://contoso.sharepoint.com/sites/Team")
#' drive |> less_contents(max_depth = 1)
#' }
less_contents <- function(x, library = NULL, path = NULL, max_depth = 0) {
  if (!is.numeric(max_depth) || length(max_depth) != 1 || is.na(max_depth) || max_depth < 0) {
    cli::cli_abort("{.arg max_depth} must be a single number, 0 or more (use {.code Inf} for everything).")
  }

  if (inherits(x, "ms_drive")) {
    drive <- x
    url_folder <- NULL
  } else {
    drive <- less_drive(x, library = library)
    url_folder <- less_parse_url(x)$folder
  }

  start <- (path %||% url_folder %||% "") |> stringr::str_remove_all("^/+|/+$")

  less_contents_walk(drive, start, depth = 0, max_depth = max_depth) |>
    dplyr::arrange(.data$path)
}

# One folder, then (if allowed) each subfolder, depth-first.
less_contents_walk <- function(drive, folder, depth, max_depth) {
  items <- drive |>
    less_list_raw(folder) |>
    less_tidy_items(folder, depth)

  if (depth >= max_depth) {
    return(items)
  }

  children <- items |>
    dplyr::filter(.data$is_folder) |>
    dplyr::pull(.data$path) |>
    purrr::map(\(p) less_contents_walk(drive, p, depth + 1, max_depth))

  dplyr::bind_rows(items, children)
}

less_list_raw <- function(drive, folder) {
  tryCatch(
    drive$list_files(if (folder == "") "/" else folder, info = "all"),
    error = function(e) {
      cli::cli_abort(c(
        "Couldn't list the folder {.val {if (folder == '') '/' else folder}}.",
        "x" = conditionMessage(e),
        "i" = "Check the folder exists and that {.arg path} is relative to the library root, e.g. {.val Budget/2025}."
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
    path        = if (folder == "") name else stringr::str_c(folder, "/", name),
    name        = name,
    is_folder   = as.logical(raw$isdir),
    depth       = depth,
    size        = as.numeric(raw$size),
    created     = less_parse_time(less_dig(raw, "createdDateTime")),
    created_by  = less_who(raw, "createdBy"),
    modified    = less_parse_time(less_dig(raw, "lastModifiedDateTime")),
    modified_by = less_who(raw, "lastModifiedBy"),
    web_url     = less_dig(raw, "webUrl"),
    id          = less_dig(raw, "id")
  )
}

less_contents_template <- function() {
  tibble::tibble(
    path = character(), name = character(), is_folder = logical(),
    depth = numeric(), size = numeric(),
    created = as.POSIXct(character(), tz = ""), created_by = character(),
    modified = as.POSIXct(character(), tz = ""), modified_by = character(),
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
