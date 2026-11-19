#' Sign in to Microsoft 365
#'
#' Gets your saved sign-in for the tenant and app in [less_details()]. The
#' first time, in an interactive session, it opens a browser so you can sign in,
#' then saves the result so later sessions (including scheduled scripts) don't
#' need the browser.
#'
#' You rarely need to call this yourself: [less_site()] and [less_drive()] call
#' it for you. The sign-in is cached for the rest of the R session.
#'
#' @param refresh Ignore the sign-in cached in this session and fetch it again?
#'
#' @return The AzureGraph login object (`ms_graph`), invisibly. Use it for
#'   anything sharepointless doesn't cover.
#' @export
#' @examples
#' \dontrun{
#' gr <- less_login()
#' gr$get_user()
#' }
less_login <- function(refresh = FALSE) {
  if (!refresh && !is.null(.less$login)) {
    return(invisible(.less$login))
  }

  details <- less_check_details()

  # Always pass `app =`. Without it AzureGraph falls back to a default app whose
  # token can see sites but not their libraries, and with more than one saved
  # login for the tenant it stops to ask which one to use.
  login <- tryCatch(
    AzureGraph::get_graph_login(details$tenant, app = details$app),
    error = function(e) NULL
  )

  if (is.null(login)) {
    if (!rlang::is_interactive()) {
      cli::cli_abort(c(
        "No saved Microsoft 365 sign-in found for your app.",
        "i" = "Run {.code sharepointless::less_login()} once in an interactive R session to sign in through your browser. After that, scripts can run without you."
      ))
    }
    cli::cli_inform(c("i" = "No saved sign-in found. Opening your browser to sign in..."))
    login <- tryCatch(
      AzureGraph::create_graph_login(details$tenant, app = details$app),
      error = function(e) {
        cli::cli_abort(
          c("Sign-in failed.", "x" = conditionMessage(e), less_guide_hint()),
          parent = NA, call = NULL
        )
      }
    )
  }

  less_check_scopes(login)
  .less$login <- login
  .less$sites <- list()
  .less$drives <- list()
  invisible(login)
}

# Warn early if the token can't reach SharePoint content, which otherwise shows
# up later as an empty list of libraries or a 403.
less_check_scopes <- function(login) {
  scopes <- tryCatch(login$token$credentials$scope, error = function(e) NULL)
  if (is.character(scopes) && !any(stringr::str_detect(scopes, "Sites\\."))) {
    cli::cli_warn(c(
      "Your sign-in has no SharePoint (Sites) permissions, so you'll be able to find sites but not open their libraries.",
      "i" = "Granted: {.val {scopes}}.",
      less_guide_hint()
    ))
  }
}

#' Open a SharePoint site
#'
#' @param url The site's address. A library address copied from the browser
#'   (ending `/Forms/AllItems.aspx`) works too: the site part is used.
#'
#' @return The Microsoft365R site object (`ms_site`). Use its methods for
#'   anything sharepointless doesn't cover. Cached for the session.
#' @export
#' @examples
#' \dontrun{
#' site <- less_site("https://contoso.sharepoint.com/sites/Team")
#' site$properties$displayName
#' }
less_site <- function(url) {
  site_url <- less_parse_url(url)$site

  if (!is.null(.less$sites[[site_url]])) {
    return(.less$sites[[site_url]])
  }

  # Go through the login's method rather than Microsoft365R::get_sharepoint_site(),
  # which asks for broad default permissions most tenants don't grant.
  site <- tryCatch(
    less_login()$get_sharepoint_site(site_url),
    error = function(e) {
      cli::cli_abort(c(
        "Couldn't open the site {.url {site_url}}.",
        "x" = conditionMessage(e),
        "i" = "Check the address opens in your browser while signed in as yourself."
      ), call = NULL)
    }
  )

  .less$sites[[site_url]] <- site
  site
}

#' Open a SharePoint document library
#'
#' Finds one document library ("drive") on a site. Pass the library's address
#' straight from your browser, or a site address plus `library`.
#'
#' @param url A library address copied from the browser (ending
#'   `/Forms/AllItems.aspx`), or a site address.
#' @param library Which library to open, as a regular expression matched
#'   against library names (case-insensitive), or a library's ID. Partial
#'   matches are fine, so you don't need to retype accents or curly
#'   apostrophes. Leave `NULL` to use the library in `url`, or the site's
#'   default library if `url` is a site address.
#'
#' @return The Microsoft365R drive object (`ms_drive`). Use its methods for
#'   anything sharepointless doesn't cover.
#' @export
#' @examples
#' \dontrun{
#' # Straight from the browser
#' drive <- less_drive("https://contoso.sharepoint.com/sites/Team/Shared%20Documents/Forms/AllItems.aspx")
#'
#' # Site plus a partial name
#' drive <- less_drive("https://contoso.sharepoint.com/sites/Team", library = "^Rapports")
#' }
less_drive <- function(url, library = NULL) {
  parsed <- less_parse_url(url)
  drives <- less_list_drives(url)
  names <- drives |> purrr::map_chr(\(d) d$properties$name)

  if (!is.null(library)) {
    by_id <- drives |> purrr::keep(\(d) identical(d$properties$id, library))
    if (length(by_id) == 1) {
      return(by_id[[1]])
    }
    hits <- stringr::str_detect(names, stringr::regex(library, ignore_case = TRUE))
    return(less_pick_one(drives[hits], names, desc = cli::format_inline("matching {.val {library}}")))
  }

  if (!is.null(parsed$library)) {
    target <- stringr::str_c(parsed$site, "/", parsed$library) |> stringr::str_to_lower()
    hits <- drives |>
      purrr::map_chr(\(d) d$properties$webUrl %||% "") |>
      utils::URLdecode() |>
      stringr::str_to_lower() |>
      purrr::map_lgl(\(u) u == target)
    return(less_pick_one(drives[hits], names, desc = cli::format_inline("at {.url {url}}")))
  }

  if (length(drives) == 1) {
    return(drives[[1]])
  }

  # Several libraries and none named: use the site's default library.
  default <- tryCatch(less_site(url)$get_drive(), error = function(e) NULL)
  if (is.null(default)) {
    cli::cli_abort(c(
      "This site has several libraries. Say which one with {.arg library}:",
      purrr::set_names(names, "*")
    ))
  }
  cli::cli_inform(c("i" = "Using the site's default library, {.val {default$properties$name}}. Pick another with {.arg library}."))
  default
}

# All document libraries on a site, cached per site.
less_list_drives <- function(url) {
  site_url <- less_parse_url(url)$site
  if (!is.null(.less$drives[[site_url]])) {
    return(.less$drives[[site_url]])
  }

  drives <- less_site(url)$list_drives()

  if (length(drives) == 0) {
    cli::cli_abort(c(
      "Found the site, but can't see any of its document libraries.",
      "i" = "This almost always means your sign-in lacks SharePoint permissions, not that the site is empty.",
      less_guide_hint()
    ), call = NULL)
  }

  .less$drives[[site_url]] <- drives
  drives
}

less_pick_one <- function(matches, all_names, desc, call = rlang::caller_env()) {
  if (length(matches) == 1) {
    return(matches[[1]])
  }
  if (length(matches) == 0) {
    cli::cli_abort(c(
      "No library {desc}. Libraries on this site:",
      purrr::set_names(all_names, "*")
    ), call = call)
  }
  cli::cli_abort(c(
    "More than one library {desc}. Make {.arg library} more specific:",
    purrr::set_names(purrr::map_chr(matches, \(d) d$properties$name), "*")
  ), call = call)
}
