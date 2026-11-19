test_that("max_depth = 0 lists only the starting folder", {
  drive <- fake_drive(example_tree())
  out <- less_contents(drive)
  expect_equal(out$name, c("Budget", "Travel.docx"))
  expect_equal(out$depth, c(0, 0))
  expect_equal(drive$calls(), "/")
})

test_that("max_depth = Inf walks every folder, including empty ones", {
  drive <- fake_drive(example_tree())
  out <- less_contents(drive, max_depth = Inf)
  expect_equal(out$path, c(
    "/Budget", "/Budget/2025", "/Budget/2025/Empty", "/Budget/2025/plan.xlsx",
    "/Budget/Rapport de l\u2019\u00e9quipe.xlsx", "/Travel.docx"
  ))
  expect_equal(out$depth, c(0, 1, 2, 2, 1, 0))
  expect_setequal(drive$calls(), c("/", "Budget", "Budget/2025", "Budget/2025/Empty"))
})

test_that("max_depth stops recursion at the right level", {
  drive <- fake_drive(example_tree())
  out <- less_contents(drive, max_depth = 1)
  expect_equal(max(out$depth), 1)
  expect_false("Budget/2025" %in% drive$calls())
})

test_that("path is the second argument and tolerates stray slashes", {
  out <- less_contents(fake_drive(example_tree()), "Budget//2025/", max_depth = 1)
  expect_equal(out$path[1], "/Budget/2025/Empty")
  expect_equal(out$depth[out$name == "plan.xlsx"], 0)
})

test_that("a path from the output goes back in as path", {
  drive <- fake_drive(example_tree())
  top <- less_contents(drive)
  out <- less_contents(drive, top$path[top$name == "Budget"])
  expect_equal(out$name, c("2025", "Rapport de l\u2019\u00e9quipe.xlsx"))
})

test_that("columns come out in the documented order and types", {
  out <- less_contents(fake_drive(example_tree()))
  expect_named(out, c(
    "name", "is_folder", "size", "modified", "modified_by",
    "created", "created_by", "depth", "path", "web_url", "id"
  ))
  expect_s3_class(out$size, "fs_bytes")
  expect_s3_class(out$modified, "POSIXct")
  expect_equal(out$created_by[1], "Lee, Pat")
})

test_that("times are parsed from UTC", {
  out <- less_contents(fake_drive(example_tree()))
  expect_equal(
    lubridate::with_tz(out$created[1], "UTC"),
    lubridate::ymd_hms("2024-12-10 13:51:07", tz = "UTC")
  )
})

test_that("sizes over 2 GB don't overflow", {
  out <- less_contents(fake_drive(example_tree()), "Budget/2025")
  expect_equal(as.numeric(out$size[out$name == "plan.xlsx"]), 3e9)
})

test_that("items made by a flow show the app's name", {
  out <- less_contents(fake_drive(example_tree()), "Budget")
  expect_equal(out$created_by[stringr::str_detect(out$name, "^Rapport")], "Nightly flow")
})

test_that("an empty folder gives an empty tibble with the usual columns", {
  out <- less_contents(fake_drive(example_tree()), "Budget/2025/Empty")
  expect_equal(nrow(out), 0)
  expect_named(out, names(less_contents(fake_drive(example_tree()))))
})

test_that("a missing folder or bad max_depth gives a plain-language error", {
  drive <- fake_drive(example_tree())
  expect_error(less_contents(drive, "Nope"), "Couldn't list the folder \"/Nope\"")
  expect_error(less_contents(drive, c("a", "b")), "single folder path")
  expect_error(less_contents(drive, max_depth = -1), "max_depth")
  expect_error(less_contents(drive, max_depth = "all"), "max_depth")
})

# A folder URL, with less_drive() swapped for the fake so nothing goes online.
folder_url <- stringr::str_c(
  "https://contoso.sharepoint.com/sites/Team/Shared%20Documents/Forms/AllItems.aspx",
  "?id=%2Fsites%2FTeam%2FShared%20Documents%2FBudget"
)

local_fake_library <- function(env = parent.frame()) {
  drive <- fake_drive(example_tree())
  local_mocked_bindings(less_drive = function(url, library = NULL) drive, .env = env)
  drive
}

test_that("a folder URL starts the listing in that folder", {
  local_fake_library()
  expect_equal(less_contents(folder_url)$path, c("/Budget/2025", "/Budget/Rapport de l\u2019\u00e9quipe.xlsx"))
})

test_that("path is relative to the URL's folder", {
  local_fake_library()
  expect_equal(less_contents(folder_url, "2025")$path, c("/Budget/2025/Empty", "/Budget/2025/plan.xlsx"))
})

test_that("a leading / goes from the top of the library", {
  local_fake_library()
  expect_equal(less_contents(folder_url, "/")$path, c("/Budget", "/Travel.docx"))
  expect_equal(less_contents(folder_url, "/Budget/2025")$name, c("Empty", "plan.xlsx"))
})

test_that("paths from the output work with a folder URL too", {
  local_fake_library()
  deeper <- less_contents(folder_url)$path[1]
  expect_equal(less_contents(folder_url, deeper)$name, c("Empty", "plan.xlsx"))
})

test_that("a missing relative folder explains paths are relative to the URL", {
  local_fake_library()
  expect_error(less_contents(folder_url, "MPIP"), "\"/Budget/MPIP\"")
  expect_error(less_contents(folder_url, "MPIP"), "relative to the folder in your URL")
  expect_no_error(try(less_contents(folder_url, "/MPIP"), silent = TRUE))
  expect_error(less_contents(folder_url, "/MPIP"), "Check the spelling")
})
