## What is this?
A simple powershell script to Bulk-import movie requests into Jellyseerr from a simple `Title,Year` CSV—no IMDb/Trakt required. I recommend reading this in a text editor, its formatted to be easily read there.


## Features
- Robust search (URL-encoded, ASCII fallback)
- Matching: exact *title+year* → exact *title* → same *year*
- Progress bar + log file
- Dry-run mode
- De-dupe + strict-year
- No external API keys (uses your Jellyseerr only)


## Requirements
- Windows PowerShell 5+ or PowerShell 7+
- Jellyseerr reachable from your machine
- Jellyseerr API key (Profile → API Key)
- CSV with headers: `Title,Year`


## How to setup
-Save the script as jellyseerr-import.ps1 and your CSV as Title,Year with one entry per line. (formatting example below)
-Update your lines 4 and 5 in jellyseerr-import.ps1 with your install values
      [string]$JellyseerrUrl = "http://localhost:5055",
      [string]$ApiKey        = "",        # pass via -ApiKey or $env:JELLYSEERR_API_KEY
-Open PowerShell in the folder with both files.


## How to run
-Open PowerShell in the folder with both files.
Commands:
    Set-ExecutionPolicy -Scope Process Bypass
    .\jellyseerr-import.ps1                     # live run
                      -or-
    .\jellyseerr-import.ps1 -Limit 20 -DryRun   # preview run


## CSV shape/format example
Title,Year
Algiers,1938
Bird of Paradise,1932
Danger Lights, 1930
Dixiana,1930


## Notes
-If requests fail with Radarr errors, set default server/profile/root in Jellyseerr (Settings → Services → Radarr).
-If you see rate limits, increase -DelayMs (e.g., 400–600).
-This is WYSiWYG, I'm posting it in hope that it saves someone the time and effort it took me to figure out. That said, you hit an issue, debug with AI, they'll get you going with your specific variables. Take care!
