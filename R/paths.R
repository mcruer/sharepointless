# Shared by every function that takes a URL and a path. See the "Paths work
# like a file system" principle in CLAUDE.md.

# The drive a URL (or drive object) points to, and `base`: the folder within
# it, relative to the library root ("" for the root).
less_locate <- function(x, library = NULL) {
  if (inherits(x, "ms_drive")) {
    return(list(drive = x, base = ""))
  }
  list(
    drive = less_drive(x, library = library),
    base = less_parse_url(x)$folder %||% ""
  )
}

# Turn a user's `path` into a path relative to the library root, without
# leading or trailing slashes ("" is the root). Like a file system: a leading
# "/" starts from the library root; anything else is relative to `base`, the
# folder the URL points to.
less_resolve_path <- function(path, base) {
  if (is.null(path)) {
    return(base)
  }
  tidy <- function(p) p |> stringr::str_replace_all("/{2,}", "/") |> stringr::str_remove_all("^/+|/+$")
  if (stringr::str_starts(path, "/")) {
    return(tidy(path))
  }
  tidy(stringr::str_c(base, "/", path))
}

# Plain-text advice for when a path isn't found. Insert into cli messages as a
# value ("{hint}"), never as a template, so names containing braces are safe.
less_path_hint <- function(path, base) {
  if (!is.null(path) && !stringr::str_starts(path, "/") && base != "") {
    cli::format_inline("{.arg path} is relative to the folder in your URL ({.val {stringr::str_c('/', base)}}). Start it with {.val /} to go from the top of the library.")
  } else {
    "Check the spelling, or use {.fn less_contents} on the folder above it to see what's there." |> cli::format_inline()
  }
}

# " in library "Documents"", or "" if the drive has no name to hand.
less_in_library <- function(drive) {
  library <- tryCatch(drive$properties$name, error = function(e) NULL)
  if (is.null(library)) "" else cli::format_inline(" in library {.val {library}}")
}
