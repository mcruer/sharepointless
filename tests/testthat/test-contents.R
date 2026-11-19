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
    "Budget", "Budget/2025", "Budget/2025/Empty", "Budget/2025/plan.xlsx",
    "Budget/Rapport de l’équipe.xlsx", "Travel.docx"
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

test_that("path starts deeper, tolerating stray slashes", {
  out <- less_contents(fake_drive(example_tree()), path = "/Budget/", max_depth = 1)
  expect_equal(out$path[1], "Budget/2025")
  expect_equal(out$depth[out$path == "Budget/2025"], 0)
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
  out <- less_contents(fake_drive(example_tree()), path = "Budget/2025")
  expect_equal(as.numeric(out$size[out$name == "plan.xlsx"]), 3e9)
})

test_that("items made by a flow show the app's name", {
  out <- less_contents(fake_drive(example_tree()), path = "Budget")
  expect_equal(out$created_by[stringr::str_detect(out$name, "^Rapport")], "Nightly flow")
})

test_that("an empty folder gives an empty tibble with the usual columns", {
  out <- less_contents(fake_drive(example_tree()), path = "Budget/2025/Empty")
  expect_equal(nrow(out), 0)
  expect_named(out, names(less_contents(fake_drive(example_tree()))))
})

test_that("a missing folder or bad max_depth gives a plain-language error", {
  drive <- fake_drive(example_tree())
  expect_error(less_contents(drive, path = "Nope"), "Couldn't list the folder")
  expect_error(less_contents(drive, max_depth = -1), "max_depth")
  expect_error(less_contents(drive, max_depth = "all"), "max_depth")
})
