# sharepointless: project brief

> Working name. Rename freely; nothing below depends on it.

## What this is

An R package that wraps Microsoft365R / AzureGraph so routine SharePoint work
takes one line instead of ten. It's a **general-purpose tool for anyone in the
Ontario Public Service (OPS)** who works with SharePoint from R, not tied to
any one branch, site or project.

The first function to build: **list the contents of a SharePoint document
library as a tidy tibble.** More functions follow as real needs show up.

Author: Geordie McRuer <geo.mcruer@gmail.com> · License: MIT.
Style: start minimal (functions + roxygen docs). Tests and vignettes come later.

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

OPS staff who have followed the setup guide ("Connecting R to SharePoint in the
OPS"): each person registers **their own** Entra app, gets its permissions
approved, and stores two IDs in `.Renviron`:

```
CLIMICROSOFT365_TENANT=<tenant GUID>      # the same for everyone in the OPS
CLIMICROSOFT365_AADAPPID=<client GUID>    # each user's own app registration
```

**Configuration:** nothing is hard-coded, not even the OPS tenant ID. Every
value comes from the user's own setup. Follow the same configuration mechanism
as Geordie's `ezekiel` package (find that repo and mirror its approach),
including how missing values are detected and reported.

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

Hard-won rules (each one cost real debugging time):
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
- Library names can contain non-ASCII characters (French titles, curly
  apostrophes U+2019). Match by regex or by ID; never require exact retyping.
- Multiple cached logins for one tenant make `get_graph_login()` prompt, which
  breaks scheduled scripts. Always pass `app =` so it picks the right one.
- Never put IDs, secrets or certificates in package code.

Verified example site: `https://ontariogov.sharepoint.com/sites/EDU-Extranet/CBSD`
(a subsite; Graph resolves it fine).

## v1 scope

1. **Connection.** Reads the two env vars; gets (or, interactively, creates) the
   graph login; caches login/site/drive objects in a package-level environment
   so repeated calls don't re-authenticate. Check env vars up front with a
   helpful error if missing.
2. **List a library's contents → tibble.** One level (`path` argument, relative
   to the library root) and recursive (`max_depth`), with `path` and `depth`
   columns. Include useful metadata (created/modified times as POSIXct,
   created/modified by, `webUrl`, `id`), flattened from
   `list_files(info = "all")`. *The exact shape of `info = "all"` is
   unverified: have Geordie run it and `glimpse()` the result first.*
3. **Escape hatch.** A way to get the raw Microsoft365R site/drive objects for
   anything the wrapper doesn't cover.

## Later (not v1)

Download/upload, SharePoint lists → tibble, item permissions (via
`do_operation()`), app-only auth for scheduled jobs (needs a certificate; not
set up anywhere yet).

## Design principles

- One-liners for common tasks; sensible defaults; pipe-friendly; tibble out.
- Fix the annoyances once: tibbles, flattened metadata, parsed times, clear
  errors.
- Leave an escape hatch to the raw R6 objects. Don't wrap everything.
- Build only what real scripts need. No speculative functions.
- Microsoft365R has a single maintainer and is updated rarely. Keep it behind
  the package's own interface so it could be swapped for httr2 + raw Graph later.
