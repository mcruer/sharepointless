# Offline stand-ins for Microsoft365R objects. Nothing here talks to Microsoft.

# A library (drive) as less_drive() sees it: only $properties is used.
fake_library <- function(name, web_url = NULL, id = name) {
  list(properties = list(name = name, webUrl = web_url, id = id))
}

# One item, as JSON shaped like list_files(info = "all") (verified live):
# people arrive nested as createdBy$user$displayName, or createdBy$application
# for items made by flows.
fake_item <- function(name, is_folder = FALSE, size = 100, by = "Lee, Pat", app = FALSE) {
  who <- if (app) {
    stringr::str_glue('{{"application":{{"displayName":"{by}"}}}}')
  } else {
    stringr::str_glue('{{"user":{{"displayName":"{by}","email":"x@example.com"}}}}')
  }
  stringr::str_glue(
    '{{"name":"{name}","size":{format(size, scientific = FALSE)},',
    '"isdir":{tolower(is_folder)},"id":"id-{name}",',
    '"createdDateTime":"2024-12-10T13:51:07Z",',
    '"lastModifiedDateTime":"2025-01-02T03:04:05Z",',
    '"webUrl":"https://example/{name}","createdBy":{who},"lastModifiedBy":{who}}}'
  )
}

# A drive whose list_files() serves a named list of folders, each a vector of
# fake_item()s. Unknown folders error like Graph does. `calls` records which
# folders were requested.
fake_drive <- function(tree) {
  calls <- character()
  drive <- list(
    list_files = function(path, info = "name") {
      calls <<- c(calls, path)
      items <- tree[[path]]
      if (is.null(items)) stop("itemNotFound")
      if (length(items) == 0) return(data.frame())
      jsonlite::fromJSON(stringr::str_c("[", stringr::str_flatten(items, ","), "]"))
    },
    calls = function() calls
  )
  structure(drive, class = "ms_drive")
}

# The tree most contents tests use:
#   Budget/
#     2025/
#       Empty/
#       plan.xlsx (3 GB)
#     Rapport de l'equipe.xlsx (curly apostrophe, made by a flow)
#   Travel.docx
example_tree <- function() {
  list(
    "/" = c(fake_item("Budget", TRUE), fake_item("Travel.docx")),
    "Budget" = c(
      fake_item("2025", TRUE),
      fake_item("Rapport de l\u2019\u00e9quipe.xlsx", by = "Nightly flow", app = TRUE)
    ),
    "Budget/2025" = c(fake_item("Empty", TRUE), fake_item("plan.xlsx", size = 3e9)),
    "Budget/2025/Empty" = character()
  )
}
