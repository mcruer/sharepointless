# sharepointless

One-line access to SharePoint document libraries from R.

sharepointless wraps [Microsoft365R](https://github.com/Azure/Microsoft365R)
and [AzureGraph](https://github.com/Azure/AzureGraph) so routine SharePoint
work doesn't need ten lines of setup: it stores your sign-in details, signs you
in once per session, opens libraries from the URL you copied out of your
browser, and explains errors in plain language. The raw Microsoft365R objects
are always one call away for anything it doesn't cover.

It works in any Microsoft 365 organization.

## Installation

```r
# install.packages("remotes")
remotes::install_github("mcruer/sharepointless")
```

## Before you start: permissions

**The main obstacle to getting started is permissions, not R.** You sign in
through your own app registration in Microsoft Entra, and that app needs
Microsoft Graph permissions (at minimum, delegated `Sites.ReadWrite.All`) that
usually only your IT department can approve. Ask them first; everything else
takes minutes.

Ontario Public Service staff: a step-by-step guide, including the service desk
ticket, is in the package:

```r
vignette("ops-setup", package = "sharepointless")
```

## Usage

```r
library(sharepointless)

# Once: save your tenant ID and app (client) ID to .Renviron
less_details_to_renviron(
  tenant = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  app    = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
)

# Open a library straight from its browser address
drive <- less_drive("https://contoso.sharepoint.com/sites/Team/Shared%20Documents/Forms/AllItems.aspx")

# Or a site plus part of the library's name
drive <- less_drive("https://contoso.sharepoint.com/sites/Team", library = "^Reports")

# List a library's contents as a tibble (max_depth = Inf for everything below)
less_contents("https://contoso.sharepoint.com/sites/Team/Shared%20Documents/Forms/AllItems.aspx",
              max_depth = 1)

# See what a URL points to (no sign-in needed)
less_url("https://contoso.sharepoint.com/sites/Team/Shared%20Documents/Forms/AllItems.aspx")

# The raw Microsoft365R objects, for anything not wrapped
site <- less_site("https://contoso.sharepoint.com/sites/Team")
gr   <- less_login()
```
