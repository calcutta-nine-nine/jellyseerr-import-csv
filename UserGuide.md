## What is this?
A simple powershell script to Bulk-import movie requests into Jellyseerr from a simple `Title,Year` CSV—no IMDb/Trakt required.

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
- Save the script as jellyseerr-import.ps1 and your CSV in the same folder. (CSV formatting example below) 
- Update lines 4 and 5 of *jellyseerr-import.ps1* with **your** installation values  
> [string]$JellyseerrUrl = "http://localhost:portnumber",

> [string]$ApiKey        = "",        # pass via -ApiKey or $env:JELLYSEERR_API_KEY

## How to run
Open PowerShell in the folder with both files.  
- Elevate permissions to run 
  >  Set-ExecutionPolicy -Scope Process Bypass

- Run the Script
  >  .\jellyseerr-import.ps1                     # live run  
  
  >  .\jellyseerr-import.ps1 -Limit 20 -DryRun   # preview run  

## CSV format example
Title,Year  
Algiers,1938  
Bird of Paradise,1932  
Danger Lights, 1930  
Dixiana,1930  

## Notes
- If requests fail with Radarr errors, set default server/profile/root in Jellyseerr (Settings → Services → Radarr).  
- If you see rate limits, increase -DelayMs (e.g., 400–600).  
- This is WYSiWYG, I'm posting it in hope that it saves someone the time and effort it took me to figure out. That said, you hit an issue, debug with AI, they'll get you going with your specific variables. Take care!
