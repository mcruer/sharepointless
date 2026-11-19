#' @keywords internal
#' @importFrom rlang %||% .data
#' @importFrom Microsoft365R ms_site
"_PACKAGE"

# Importing from Microsoft365R guarantees it loads with this package. On load it
# adds the SharePoint methods (e.g. $get_sharepoint_site()) to AzureGraph's
# login object, which less_site() relies on.

# Package-level cache: one sign-in per session, plus every site and drive list
# already fetched, so repeated calls don't go back to Microsoft.
.less <- rlang::new_environment(list(login = NULL, sites = list(), drives = list()))

# Where users are sent when setup is the problem.
less_guide_hint <- function() {
  c(
    "i" = "Most first-time problems are permissions on your app registration, which your IT department has to approve.",
    "i" = "OPS staff: see {.code vignette(\"ops-setup\", package = \"sharepointless\")}."
  )
}
