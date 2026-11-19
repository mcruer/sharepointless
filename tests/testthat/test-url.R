site <- "https://contoso.sharepoint.com/sites/Team"

test_that("site addresses parse to a site only", {
  expect_equal(less_parse_url(site), list(site = site, library = NULL, folder = NULL))
  expect_equal(less_parse_url(stringr::str_c(site, "/"))$site, site)
  expect_equal(less_parse_url(stringr::str_c(site, "/SitePages/Home.aspx"))$site, site)
})

test_that("library view addresses split into site and library", {
  parts <- less_parse_url(stringr::str_c(site, "/Shared%20Documents/Forms/AllItems.aspx?viewid=abc"))
  expect_equal(parts$site, site)
  expect_equal(parts$library, "Shared Documents")
  expect_null(parts$folder)
})

test_that("subsites keep every level of the site path", {
  parts <- less_parse_url(stringr::str_c(site, "/Sub/Reports/Forms/AllItems.aspx"))
  expect_equal(parts$site, stringr::str_c(site, "/Sub"))
  expect_equal(parts$library, "Reports")
})

test_that("folder addresses give the folder relative to the library", {
  url <- stringr::str_c(
    "https://contoso.sharepoint.com/sites/Team%2DA/Sub/Shared%20Documents/Forms/AllItems.aspx",
    "?id=%2Fsites%2FTeam%2DA%2FSub%2FShared%20Documents%2FCapital%20Program%2F2025&viewid=x"
  )
  expect_equal(less_parse_url(url)$folder, "Capital Program/2025")
})

test_that("an id at the library root means no folder", {
  url <- stringr::str_c(site, "/Shared%20Documents/Forms/AllItems.aspx?id=%2Fsites%2FTeam%2FShared%20Documents")
  expect_null(less_parse_url(url)$folder)
})

test_that("non-SharePoint input gets a plain-language error", {
  expect_error(less_parse_url("http://example.com"), "SharePoint address")
  expect_error(less_parse_url(c(site, site)), "SharePoint address")
  expect_error(less_parse_url(NA_character_), "SharePoint address")
})

test_that("less_url() returns the parts and prints them", {
  parts <- less_url(stringr::str_c(site, "/Shared%20Documents/Forms/AllItems.aspx"))
  expect_s3_class(parts, "less_url")
  expect_equal(parts$library, "Shared Documents")
  expect_snapshot(print(parts))
  expect_snapshot(print(less_url(site)))
})
