# Sign-in details --------------------------------------------------------------
#
# Mirrors ezekiel's ezql_details() / ezql_details_to_rprofile() pattern, with
# one difference: values live in .Renviron, not .Rprofile, because these are
# the environment variables Microsoft365R itself reads. One source of truth.

less_env_vars <- c(tenant = "CLIMICROSOFT365_TENANT", app = "CLIMICROSOFT365_AADAPPID")

guid_pattern <- "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

#' Get the stored sign-in details
#'
#' Returns the tenant ID and app (client) ID that sharepointless signs in with.
#' Both are read from the environment variables `CLIMICROSOFT365_TENANT` and
#' `CLIMICROSOFT365_AADAPPID`, normally set in your `.Renviron` file with
#' [less_details_to_renviron()].
#'
#' Neither ID is a secret, but there's no reason to paste them into scripts.
#'
#' @return A one-row tibble with columns `tenant` and `app`. Missing values are
#'   empty strings.
#' @export
#' @examples
#' less_details()
less_details <- function() {
  tibble::tibble(
    tenant = Sys.getenv(less_env_vars[["tenant"]]),
    app    = Sys.getenv(less_env_vars[["app"]])
  )
}

#' Save sign-in details to your .Renviron
#'
#' Writes your tenant ID and app (client) ID to the `.Renviron` file in your R
#' home directory, so every future session can find them. The values are also
#' set for the current session, so you don't need to restart R.
#'
#' Both IDs are on the **Overview** page of your app registration in the
#' Microsoft Entra admin centre or Azure portal.
#'
#' @param tenant Directory (tenant) ID: a 36-character GUID.
#' @param app Application (client) ID of *your* app registration: a
#'   36-character GUID.
#' @param overwrite If `.Renviron` already has either value, replace it?
#'   Defaults to `FALSE`, which stops with an error instead.
#'
#' @return The path to `.Renviron`, invisibly.
#' @export
#' @examples
#' \dontrun{
#' less_details_to_renviron(
#'   tenant = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#'   app    = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#' )
#' }
less_details_to_renviron <- function(tenant, app, overwrite = FALSE) {
  values <- c(tenant = tenant, app = app) |> stringr::str_trim() |> purrr::set_names(c("tenant", "app"))
  bad <- values |> purrr::discard(\(v) stringr::str_detect(v, guid_pattern)) |> names()
  if (length(bad) > 0) {
    cli::cli_abort(c(
      "{.arg {bad}} must be a 36-character ID like {.val xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}.",
      "i" = "Copy it from the Overview page of your app registration. No quotes or angle brackets."
    ))
  }

  renviron <- less_renviron_path()
  current <- if (fs::file_exists(renviron)) readr::read_lines(renviron) else character()
  var_pattern <- stringr::str_c("^\\s*(", stringr::str_flatten(less_env_vars, "|"), ")\\s*=")
  existing <- stringr::str_subset(current, var_pattern)

  if (length(existing) > 0 && !overwrite) {
    cli::cli_abort(c(
      "{.file {renviron}} already has sign-in details:",
      purrr::set_names(existing, "*"),
      "i" = "To replace them, rerun with {.code overwrite = TRUE}."
    ))
  }

  new_lines <- stringr::str_c(less_env_vars, "=", values)
  current |>
    stringr::str_subset(var_pattern, negate = TRUE) |>
    c(new_lines) |>
    readr::write_lines(renviron)

  rlang::exec(Sys.setenv, !!!purrr::set_names(as.list(values), less_env_vars))
  .less$login <- NULL

  cli::cli_alert_success("Saved sign-in details to {.file {renviron}} and set them for this session.")
  invisible(renviron)
}

# Stops with a plain-language error if either ID is missing or malformed.
# Returns less_details() when all is well.
less_check_details <- function(call = rlang::caller_env()) {
  details <- less_details()
  values <- c(tenant = details$tenant, app = details$app)

  missing <- values |> purrr::keep(\(v) v == "") |> names()
  if (length(missing) > 0) {
    cli::cli_abort(c(
      "R can't find your SharePoint sign-in details.",
      "x" = "Not set: {.envvar {less_env_vars[missing]}}.",
      "i" = "Save them once with {.run sharepointless::less_details_to_renviron()}, using the IDs on your app registration's Overview page.",
      "i" = "If you added them to {.file .Renviron} by hand, save the file and restart R."
    ), call = call)
  }

  malformed <- values |> purrr::discard(\(v) stringr::str_detect(v, guid_pattern)) |> names()
  if (length(malformed) > 0) {
    cli::cli_abort(c(
      "Your sign-in details don't look like IDs.",
      "x" = "{.envvar {less_env_vars[malformed]}} should be 36 characters like {.val xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}.",
      "i" = "Check for quotes, angle brackets or leftover placeholders in {.file .Renviron}, or rerun {.fn less_details_to_renviron} with {.code overwrite = TRUE}."
    ), call = call)
  }

  details
}

# The .Renviron R reads at startup (on Windows, usually in Documents). A
# function so tests can point it at a temporary file.
less_renviron_path <- function() {
  fs::path_home_r(".Renviron")
}
