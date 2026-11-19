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
