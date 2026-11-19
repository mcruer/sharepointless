site <- "https://contoso.sharepoint.com/sites/Team"

local_libraries <- function(env = parent.frame()) {
  libraries <- list(
    fake_library("Documents", stringr::str_c(site, "/Shared%20Documents"), "b!docs"),
    fake_library("Rapports de l’équipe", stringr::str_c(site, "/Rapports"), "b!rap"),
    fake_library("Reports", stringr::str_c(site, "/Reports"), "b!rep"),
    fake_library("Reports archive", stringr::str_c(site, "/Reports%20archive"), "b!arc")
  )
  local_mocked_bindings(less_list_drives = function(url) libraries, .env = env)
}

name_of <- function(drive) drive$properties$name

test_that("a library view address opens that library, by its address", {
  local_libraries()
  expect_equal(name_of(less_drive(stringr::str_c(site, "/Shared%20Documents/Forms/AllItems.aspx"))), "Documents")
  expect_equal(name_of(less_drive(stringr::str_c(site, "/Reports%20archive/Forms/AllItems.aspx"))), "Reports archive")
})

test_that("library = matches the shown name or the address name", {
  local_libraries()
  expect_equal(name_of(less_drive(site, library = "^documents$")), "Documents")
  expect_equal(name_of(less_drive(site, library = "Shared Documents")), "Documents")
})

test_that("library = matches partially, so accents and curly apostrophes needn't be retyped", {
  local_libraries()
  expect_equal(name_of(less_drive(site, library = "^rapports")), "Rapports de l’équipe")
})

test_that("library = accepts a library ID", {
  local_libraries()
  expect_equal(name_of(less_drive(site, library = "b!arc")), "Reports archive")
})

test_that("ambiguous or unmatched library = lists the choices", {
  local_libraries()
  expect_error(less_drive(site, library = "report"), "More than one")
  expect_error(less_drive(site, library = "zzz"), "Reports archive")
  expect_error(less_drive(stringr::str_c(site, "/Nope/Forms/AllItems.aspx")), "No library")
})

test_that("a site address uses the site's default library", {
  local_libraries()
  local_mocked_bindings(less_site = function(url) list(get_drive = function() fake_library("Documents")))
  expect_message(drive <- less_drive(site), "default library")
  expect_equal(name_of(drive), "Documents")
})

test_that("a site with one library just uses it", {
  local_mocked_bindings(less_list_drives = function(url) list(fake_library("Only one")))
  expect_equal(name_of(less_drive(site)), "Only one")
})
