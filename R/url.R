# Split a pasted SharePoint URL into its site and (if present) library parts.
#
# Accepts:
#   https://contoso.sharepoint.com/sites/Team
#   https://contoso.sharepoint.com/sites/Team/Sub/
#   https://contoso.sharepoint.com/sites/Team/Shared%20Documents/Forms/AllItems.aspx
#   https://contoso.sharepoint.com/sites/Team/Reports/Forms/AllItems.aspx?id=...
#
# After clicking into a folder, the browser adds ?id=<server-relative path>,
# e.g. id=%2Fsites%2FTeam%2FShared%20Documents%2FBudget%2F2025. `folder` is that
# path relative to the library root ("Budget/2025"), or NULL.
#
# A library view URL always ends <library>/Forms/<view>.aspx, so everything
# before the library segment is the site. `library` is the library's URL
# segment, decoded ("Shared Documents"), which is NOT always its display name
# ("Documents"); less_drive() matches it against each drive's webUrl.
less_parse_url <- function(url, call = rlang::caller_env()) {
  if (!rlang::is_string(url) || !stringr::str_detect(url, "^https://[^/]+\\.sharepoint\\.com")) {
    cli::cli_abort(c(
      "{.arg url} must be a SharePoint address starting {.val https://<something>.sharepoint.com}.",
      "i" = "Copy it from your browser's address bar while viewing the site or library."
    ), call = call)
  }

  clean <- url |>
    stringr::str_trim() |>
    stringr::str_remove("[?#].*$")

  view <- stringr::str_match(clean, "^(.+)/([^/]+)/Forms/[^/]+\\.aspx$")

  if (!is.na(view[1, 1])) {
    site <- view[1, 2]
    library <- utils::URLdecode(view[1, 3])
    return(list(site = site, library = library, folder = less_url_folder(url, site, library)))
  }

  list(
    site = clean |>
      stringr::str_remove("/SitePages/.*$") |>
      stringr::str_remove("/+$"),
    library = NULL,
    folder = NULL
  )
}

less_url_folder <- function(url, site, library) {
  id <- stringr::str_match(url, "[?&]id=([^&#]+)")[1, 2]
  if (is.na(id)) {
    return(NULL)
  }
  id <- id |> stringr::str_replace_all("\\+", " ") |> utils::URLdecode()
  root <- stringr::str_c(utils::URLdecode(stringr::str_remove(site, "^https://[^/]+")), "/", library)

  if (!stringr::str_starts(stringr::str_to_lower(id), stringr::fixed(stringr::str_to_lower(root)))) {
    return(NULL)
  }
  folder <- id |> stringr::str_sub(stringr::str_length(root) + 1) |> stringr::str_remove_all("^/+|/+$")
  if (folder == "") NULL else folder
}

#' Take a SharePoint URL apart
#'
#' Shows which site, library and folder a SharePoint address points to. Paste
#' whatever is in your browser's address bar. Nothing is sent to Microsoft:
#' this only reads the address.
#'
#' Every `less_` function already accepts any of these addresses and does this
#' itself. Use `less_url()` to check what an address contains, or to get the
#' site address out of a library or folder address.
#'
#' @param url A SharePoint address: a site, a library view (containing
#'   `/Forms/`), or a folder inside one (a library view with `?id=...`).
#'
#' @return A list with:
#'   * `site`: the site's address
#'   * `library`: the library's name **as it appears in addresses**, e.g.
#'     `"Shared Documents"` for the library shown as "Documents". `NULL` for a
#'     site address.
#'   * `folder`: the folder's path within the library, e.g. `"Budget/2025"`.
#'     `NULL` if the address isn't inside a folder.
#'
#'   It prints as a short summary.
#' @export
#' @examples
#' less_url("https://contoso.sharepoint.com/sites/Team")
#'
#' parts <- less_url(paste0(
#'   "https://contoso.sharepoint.com/sites/Team/Shared%20Documents/Forms/AllItems.aspx",
#'   "?id=%2Fsites%2FTeam%2FShared%20Documents%2FBudget%2F2025"
#' ))
#' parts
#' parts$site
less_url <- function(url) {
  structure(less_parse_url(url), class = "less_url")
}

#' @export
print.less_url <- function(x, ...) {
  library <- if (is.null(x$library)) "{.emph none (this is a site address)}" else "{.val {x$library}}"
  folder <- dplyr::case_when(
    !is.null(x$folder) ~ "{.val {x$folder}}",
    !is.null(x$library) ~ "{.emph none (library root)}",
    .default = NA_character_
  )
  items <- c(Site = "{.url {x$site}}", Library = library, Folder = folder)
  cli::cli_h3("SharePoint URL")
  cli::cli_dl(items[!is.na(items)])
  invisible(x)
}
