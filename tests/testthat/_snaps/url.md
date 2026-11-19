# less_url() returns the parts and prints them

    Code
      print(parts)
    Message
      
      -- SharePoint URL 
      Site: <https://contoso.sharepoint.com/sites/Team>
      Library: "Shared Documents"
      Folder: none (library root)

---

    Code
      print(less_url(site))
    Message
      
      -- SharePoint URL 
      Site: <https://contoso.sharepoint.com/sites/Team>
      Library: none (this is a site address)

