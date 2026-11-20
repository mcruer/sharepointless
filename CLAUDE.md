# sharepointless: project brief

## What this is

An R package that wraps Microsoft365R / AzureGraph so routine SharePoint work
takes one line instead of ten. It's a **general-purpose tool for anyone in any
Microsoft 365 organization** who works with SharePoint from R. Keep it free of
anything specific to Geordie's work (sites, libraries, business logic): that
belongs in his work-specific packages, not here. The one OPS-specific piece is
the setup guide vignette (`vignettes/ops-setup.Rmd`), labelled as such.

All exported functions start with `less_`.

The first function to build: **list the contents of a SharePoint document
library as a tidy tibble.** More functions follow as real needs show up.

Author: Geordie McRuer <geo.mcruer@gmail.com> · License: MIT.
Style: functions + roxygen docs, with offline testthat tests.

## Tests

`tests/testthat/` runs fully offline: `helper-fakes.R` builds fake libraries
and drives (`fake_drive()` serves JSON shaped like the live
`list_files(info = "all")` output), and tests swap internals with
`local_mocked_bindings()` (`less_list_drives`, `less_site`,
`less_renviron_path`). Never let a test read or write the real `.Renviron`
or call Microsoft. Add a test with every new function or bug fix. Geordie
runs them with `devtools::test()`.

## Who's writing it and how

- Geordie is an experienced R/tidyverse developer (not a CS background).
  **Use tidyverse throughout**: tibbles, dplyr, purrr (`map()` and friends, never
  `apply`), stringr, lubridate (`today()`, not `Sys.time()`). Avoid base-R idioms
  where a tidyverse equivalent exists.
- He develops on **Windows** in RStudio. Claude Code runs in a cloud Linux
  sandbox with **no access to the OPS tenant**, so nothing here can be run live
  from the sandbox. Write code Geordie can test locally, and be explicit about
  what is verified vs. assumed.

## Who uses it

Anyone whose IT department has approved an app registration for them. The main
obstacle is permissions, not R; docs should say so. OPS staff have a full guide
(`vignette("ops-setup")`). Each person registers **their own** Entra app, gets
its permissions approved, and stores two IDs in `.Renviron`:

```
CLIMICROSOFT365_TENANT=<tenant GUID>      # the same for everyone in an organization
CLIMICROSOFT365_AADAPPID=<client GUID>    # each user's own app registration
```

**Configuration:** nothing is hard-coded, not even a tenant ID. Every value
comes from the user's own setup. Mirrors `ezekiel`'s `ezql_details()` /
`ezql_details_to_rprofile()` pattern as `less_details()` /
`less_details_to_renviron()`, but writes to `.Renviron` rather than
`.Rprofile`, because these are the env vars Microsoft365R itself reads.

Assume users are competent in R but have never touched Entra, OAuth or Graph.
Error messages should say what to do, in plain language, and point to the guide
where relevant.

## Auth: the pattern that works (verified 2026-11-19)

Delegated sign-in as the user:

```r
# one-time, interactive
gr <- AzureGraph::create_graph_login(Sys.getenv("CLIMICROSOFT365_TENANT"),
                                     app = Sys.getenv("CLIMICROSOFT365_AADAPPID"))
# every session
gr <- AzureGraph::get_graph_login(Sys.getenv("CLIMICROSOFT365_TENANT"),
                                  app = Sys.getenv("CLIMICROSOFT365_AADAPPID"))
site <- gr$get_sharepoint_site("https://ontariogov.sharepoint.com/sites/<Site>")
drive <- site$list_drives() |>
  purrr::keep(\(d) stringr::str_detect(d$properties$name, "<pattern>")) |>
  purrr::pluck(1)
drive$list_files()   # data.frame: name, size, isdir, id
```

Hard-won rules (each one cost real debugging time). These are AzureGraph /
Microsoft365R behaviours, so they apply in any tenant, not just the OPS:
- **Always pass `app =`.** Without it AzureGraph uses a default app (Azure CLI
  ID) whose token has no Sites/Files scopes. The site resolves, but
  `list_drives()` returns nothing and `get_drive()` gives a 403.
- **`get_graph_login()` only retrieves.** The first run needs
  `create_graph_login()`; the package should do this automatically when no
  cached login exists, in interactive sessions only.
- **Don't call `Microsoft365R::get_sharepoint_site()` directly.** Its default
  scopes (`Group.ReadWrite.All`, `Directory.Read.All`, `Sites.Manage.All`) aren't
  granted. Go through the graph login's `$get_sharepoint_site()` method.
- `get_drive("name")` internally calls `list_drives()` and errors confusingly
  (`argument to 'which' is not logical`) when that comes back empty.
- Users paste **library view URLs** (`.../Shared%20Documents/Forms/AllItems.aspx`)
  as site URLs. Accepting either, and splitting out the site and library, would
  remove a common failure.
- Library names can contain non-ASCII characters (accents, curly
  apostrophes U+2019). Match by regex or by ID; never require exact retyping.
- Multiple cached logins for one tenant make `get_graph_login()` prompt, which
  breaks scheduled scripts. Always pass `app =` so it picks the right one.
- Never put IDs, secrets or certificates in package code.

Subsites (`/sites/A/B`) resolve fine through Graph.

## Status (2026-11-19)

v1 is built. `less_details()`, `less_details_to_renviron()`, `less_login()`,
`less_site()`, `less_drive()` (accepts library view URLs; `library =` is a
case-insensitive regex or a drive ID; defaults to the site's default library)
are verified live by Geordie. `less_url()` (parse only, prints site/library/folder) is tested in the sandbox.
`less_contents()` verified live 2026-11-19: folder from a pasted URL, relative
`path` ("MPIP" inside the URL's folder), `"/"` for the library root,
`max_depth = 1`, folder names with spaces. Full test suite (78 expectations)
passes on Geordie's Windows machine against the real Microsoft365R.

`less_read(x, path, .f, ..., library)`, `less_read_excel()`, `less_read_csv()`
verified live 2026-11-19 (multi-sheet xlsx, `sheet =`, a plain function as
`.f`). `.f` also takes purrr-style `~ .x` lambdas via `rlang::as_function()`. They download with `drive$download_file(src, dest, overwrite)`
(signature read from Microsoft365R's source: `src` is relative to the library
root; it removes partial files on failure and refuses folders) to a temp file
that keeps the extension, call `.f(temp, ...)`, and always delete the temp file.
Shared URL/path plumbing lives in `R/paths.R` (`less_locate()`,
`less_resolve_path()`, `less_path_hint()`): use it for every new function.

`list_files(info = "all")` shape (verified live): data.frame with `name`,
`size` (int), `isdir`, `id`, `@microsoft.graph.downloadUrl`,
`createdDateTime` / `lastModifiedDateTime` (chr, ISO 8601 UTC), `eTag`,
`webUrl`, `cTag`, `isAuthoritative`, and nested data-frame columns
`createdBy` / `lastModifiedBy` (1 col: `user`), `parentReference` (6),
`file` (2), `fileSystemInfo` (2), `shared` (1). Columns can vary by folder
(e.g. `folder` vs `file`), so dig defensively.

## v1 scope

1. **Connection.** Reads the two env vars; gets (or, interactively, creates) the
   graph login; caches login/site/drive objects in a package-level environment
   so repeated calls don't re-authenticate. Check env vars up front with a
   helpful error if missing.
2. **List a library's contents → tibble** (`less_contents(x, path, max_depth,
   library)`). One level or recursive (`max_depth`), with absolute `path`,
   `folder` (containing folder's path, so items join to their folder's row),
   lower-case `extension`, and `depth` (from the starting folder) columns,
   created/modified times as local POSIXct, created/modified by, `web_url`,
   `id`.
3. **Escape hatch.** A way to get the raw Microsoft365R site/drive objects for
   anything the wrapper doesn't cover.

## Conventions in chat

Geordie keeps a SharePoint address in a global variable called `url`
(currently a folder URL). In code examples, use `url` rather than a
placeholder URL.
Never write to the user's global environment from package code.

## Later (not v1)

Writing back (`less_write(x, path, data, .f)` + wrappers, mirroring
`less_read`), downloading files to disk, SharePoint lists → tibble, item permissions (via
`do_operation()`), app-only auth for scheduled jobs (needs a certificate; not
set up anywhere yet).

## Design principles

- **Any URL in, the right thing out.** Every `less_` function takes any
  SharePoint URL (site, library view, or folder view) as its first argument
  and works out the site/library/folder itself. Users keep one variable per
  place and never take URLs apart. Don't add helpers that return URL pieces
  for passing between functions; `less_url()` exists only as a diagnostic.
- **Paths work like a file system.** `path` is relative to wherever the URL
  points (its folder, else the library root); a leading `/` means the library
  root. Outputs report paths absolute, with a leading `/`, so any `path` value
  from a result can be fed straight back in, whatever URL is used.
- **Argument order: URL, then path, then options, then `library`.** The thing
  users change most comes second (`less_contents(url, "MPIP")`). `library` is
  a rare override near the end, except in `less_drive()`, whose job it is.
- One-liners for common tasks; sensible defaults; pipe-friendly; tibble out.
- Fix the annoyances once: tibbles, flattened metadata, parsed times, clear
  errors.
- Leave an escape hatch to the raw R6 objects. Don't wrap everything.
- Build only what real scripts need. No speculative functions.
- Microsoft365R has a single maintainer and is updated rarely. Keep it behind
  the package's own interface so it could be swapped for httr2 + raw Graph later.
