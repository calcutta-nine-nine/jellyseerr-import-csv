# jellyseerr-import.ps1
Bulk-import movie requests into Jellyseerr from a simple `Title,Year` CSV—no IMDb/Trakt required.


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


## Quick start
```powershell
# optional: store key in env
$env:JELLYSEERR_API_KEY = "<your key>"

# run
Set-ExecutionPolicy -Scope Process Bypass
.\jellyseerr-import.ps1 -Limit 20 -DryRun   # preview
.\jellyseerr-import.ps1                     # go live


## CSV shape/format example
Title,Year
Algiers,1938
Bird of Paradise,1932
Danger Lights, 1930
Dixiana,1930

## Notes
If requests fail with Radarr errors, set default server/profile/root in Jellyseerr (Settings → Services → Radarr).

If you see rate limits, increase -DelayMs (e.g., 400–600).