# Split a pasted SharePoint URL into its site and (if present) library parts.
#
# Accepts:
#   https://contoso.sharepoint.com/sites/Team
#   https://contoso.sharepoint.com/sites/Team/Sub/
#   https://contoso.sharepoint.com/sites/Team/Shared%20Documents/Forms/AllItems.aspx
#   https://contoso.sharepoint.com/sites/Team/Reports/Forms/AllItems.aspx?id=...
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
    return(list(site = view[1, 2], library = utils::URLdecode(view[1, 3])))
  }

  list(
    site = clean |>
      stringr::str_remove("/SitePages/.*$") |>
      stringr::str_remove("/+$"),
    library = NULL
  )
}
