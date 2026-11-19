good_tenant <- "12345678-1234-1234-1234-123456789012"
good_app <- "abcdef12-1234-1234-1234-123456789012"

# Point less_details_to_renviron() at a temporary file, never the real one.
# With no `lines`, the file doesn't exist yet.
local_renviron <- function(lines = NULL, env = parent.frame()) {
  path <- withr::local_tempfile(lines = lines, .local_envir = env)
  local_mocked_bindings(less_renviron_path = function() path, .env = env)
  withr::local_envvar(CLIMICROSOFT365_TENANT = NA, CLIMICROSOFT365_AADAPPID = NA, .local_envir = env)
  path
}

test_that("less_details() reads the two environment variables", {
  withr::local_envvar(CLIMICROSOFT365_TENANT = good_tenant, CLIMICROSOFT365_AADAPPID = good_app)
  expect_equal(less_details(), tibble::tibble(tenant = good_tenant, app = good_app))
})

test_that("missing details give an error naming what's missing", {
  withr::local_envvar(CLIMICROSOFT365_TENANT = good_tenant, CLIMICROSOFT365_AADAPPID = NA)
  expect_error(less_check_details(), "CLIMICROSOFT365_AADAPPID")
})

test_that("placeholders left in .Renviron are caught", {
  withr::local_envvar(CLIMICROSOFT365_TENANT = "<tenant>", CLIMICROSOFT365_AADAPPID = good_app)
  expect_error(less_check_details(), "don't look like IDs")
})

test_that("less_details_to_renviron() writes, keeps other lines, and sets the session", {
  path <- local_renviron(lines = "OTHER=1")
  expect_message(less_details_to_renviron(good_tenant, good_app), "Saved")
  expect_equal(
    readr::read_lines(path),
    c("OTHER=1", stringr::str_c("CLIMICROSOFT365_TENANT=", good_tenant), stringr::str_c("CLIMICROSOFT365_AADAPPID=", good_app))
  )
  expect_equal(less_details()$tenant, good_tenant)
})

test_that("less_details_to_renviron() creates .Renviron if there isn't one", {
  path <- local_renviron()
  expect_false(fs::file_exists(path))
  suppressMessages(less_details_to_renviron(good_tenant, good_app))
  expect_true(fs::file_exists(path))
})

test_that("existing details are only replaced with overwrite = TRUE", {
  path <- local_renviron()
  suppressMessages(less_details_to_renviron(good_tenant, good_app))
  new_tenant <- "99999999-1234-1234-1234-123456789012"
  expect_error(less_details_to_renviron(new_tenant, good_app), "overwrite = TRUE")
  suppressMessages(less_details_to_renviron(new_tenant, good_app, overwrite = TRUE))
  lines <- readr::read_lines(path)
  expect_length(lines, 2)
  expect_true(stringr::str_c("CLIMICROSOFT365_TENANT=", new_tenant) %in% lines)
})

test_that("malformed IDs are refused before anything is written", {
  path <- local_renviron()
  expect_error(less_details_to_renviron("abc", good_app), "tenant")
  expect_error(less_details_to_renviron(good_tenant, "<app>"), "app")
  expect_false(fs::file_exists(path))
})

test_that("surrounding spaces are trimmed", {
  path <- local_renviron()
  suppressMessages(less_details_to_renviron(stringr::str_c(" ", good_tenant, " "), good_app))
  expect_equal(less_details()$tenant, good_tenant)
})
