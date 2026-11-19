folder_url <- stringr::str_c(
  "https://contoso.sharepoint.com/sites/Team/Shared%20Documents/Forms/AllItems.aspx",
  "?id=%2Fsites%2FTeam%2FShared%20Documents%2FBudget"
)

local_fake_files <- function(env = parent.frame()) {
  drive <- fake_drive(example_tree(), example_files())
  local_mocked_bindings(less_drive = function(url, library = NULL) drive, .env = env)
  drive
}

test_that("less_read_excel() reads a sheet, with paths relative to the URL's folder", {
  local_fake_files()
  out <- less_read_excel(folder_url, "2025/plan.xlsx")
  expect_equal(out, tibble::tibble(school = c("A", "B"), cost = c(1.5, 2)))
  expect_equal(less_read_excel(folder_url, "2025/plan.xlsx", sheet = "Notes")$note, "x")
})

test_that("a leading / or a path from less_contents() works", {
  drive <- local_fake_files()
  expect_equal(nrow(less_read_excel(folder_url, "/Budget/2025/plan.xlsx")), 2)
  listed <- less_contents(drive, "Budget/2025")
  expect_equal(nrow(less_read_excel(drive, listed$path[listed$name == "plan.xlsx"])), 2)
})

test_that("read_excel()'s options are passed through", {
  local_fake_files()
  out <- suppressMessages(less_read_excel(folder_url, "2025/plan.xlsx", skip = 1, col_names = FALSE, n_max = 1))
  expect_equal(out[[1]], "A")
  expect_equal(names(less_read_excel(folder_url, "2025/plan.xlsx", .name_repair = toupper)), c("SCHOOL", "COST"))
})

test_that("the downloaded copy keeps its extension and is deleted afterwards", {
  drive <- local_fake_files()
  less_read_excel(folder_url, "2025/plan.xlsx")
  expect_equal(fs::path_ext(drive$downloads()), "xlsx")
  expect_false(any(fs::file_exists(drive$downloads())))
})

test_that("less_read_csv() reads a CSV with read_csv()'s options", {
  local_fake_files()
  out <- less_read_csv(folder_url, "/Travel.csv", show_col_types = FALSE)
  expect_equal(out$trip, c("Ottawa", NA))
  expect_equal(less_read_csv(folder_url, "/Travel.csv", col_types = "cc")$km, c("450", "0"))
})

test_that("less_read() takes any reading function, including lambdas", {
  local_fake_files()
  expect_equal(
    less_read(folder_url, "/Travel.csv", readr::read_lines),
    c("trip,km", "Ottawa,450", "NA,0")
  )
  expect_equal(
    less_read(folder_url, "2025/plan.xlsx", \(file) readxl::excel_sheets(file)),
    c("Summary", "Notes")
  )
  expect_equal(less_read(folder_url, "2025/plan.xlsx", readxl::excel_sheets), c("Summary", "Notes"))
})

test_that("less_read() takes purrr-style ~ .x lambdas", {
  local_fake_files()
  expect_equal(less_read(folder_url, "2025/plan.xlsx", ~ readxl::excel_sheets(.x)), c("Summary", "Notes"))
  expect_equal(less_read(folder_url, "2025/plan.xlsx", ~ readxl::read_excel(.x, sheet = 2))$note, "x")
  expect_error(less_read(folder_url, "2025/old.xls", ~ readxl::read_excel(.x)), "~readxl::read_excel\\(.x\\)")
})

test_that("a missing file says where it looked and how paths work", {
  drive <- local_fake_files()
  expect_error(less_read_excel(folder_url, "plan.xlsx"), "\"/Budget/plan.xlsx\"")
  expect_error(less_read_excel(folder_url, "plan.xlsx"), "relative to the folder in your URL")
  expect_false(any(fs::file_exists(drive$downloads())))
})

test_that("a folder instead of a file gives a clear error", {
  local_fake_files()
  expect_error(less_read_excel(folder_url, "2025"), "only applicable for a file")
})

test_that("a file the reader can't handle names the file and the reader, and cleans up", {
  drive <- local_fake_files()
  expect_error(less_read_excel(folder_url, "2025/old.xls"), "couldn't read it")
  expect_error(less_read_excel(folder_url, "2025/old.xls"), "readxl::read_excel")
  expect_false(any(fs::file_exists(drive$downloads())))
})

test_that("path and .f are checked up front", {
  local_fake_files()
  expect_error(less_read_excel(folder_url), "must be the file to read")
  expect_error(less_read_excel(folder_url, "/"), "must be the file to read")
  expect_error(less_read(folder_url, "/Travel.csv"), "must be a function")
  expect_error(less_read(folder_url, "/Travel.csv", "read_csv"), "must be a function")
})
