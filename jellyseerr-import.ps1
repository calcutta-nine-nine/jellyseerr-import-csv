# jellyseerr-import.ps1 — Progress + logging + robust search (URL-encoded + ASCII fallback)
[CmdletBinding()]
param(
  [string]$JellyseerrUrl = "http://localhost:5055",
  [string]$ApiKey        = "",        # pass via -ApiKey or $env:JELLYSEERR_API_KEY
  [int]$DelayMs          = 400,       # wait between rows
  [int]$Limit            = 0,         # rows to process (0 = all)
  [switch]$DryRun        # show actions, skip POST
)

# ===== Fixed CSV schema =====
$Delimiter  = ','
$TitleCol   = 'Title'
$YearCol    = 'Year'
$StrictYear = $true
$DeDupe     = $true

# ===== Load API key from env if not provided =====
if (-not $ApiKey -and $env:JELLYSEERR_API_KEY) { $ApiKey = $env:JELLYSEERR_API_KEY }
if (-not $ApiKey) { Write-Host "NOTE: No API key set. Use -ApiKey or `$env:JELLYSEERR_API_KEY." -ForegroundColor Yellow }

# ===== File picker =====
Add-Type -AssemblyName System.Windows.Forms
$dlg = New-Object System.Windows.Forms.OpenFileDialog
$dlg.Title  = "Select your movies CSV (Title,Year)"
$dlg.Filter = "CSV|*.csv|All files|*.*"
if ($dlg.ShowDialog() -ne "OK") { throw "No file selected." }
$InputCsv = $dlg.FileName
$OutDir   = Split-Path $InputCsv
$OutCsv   = Join-Path $OutDir "results.csv"
$LogFile  = Join-Path $OutDir "results.log"

# ===== Helpers =====
function Log([string]$msg, [ConsoleColor]$color = [ConsoleColor]::Gray) {
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $line = "[$ts] $msg"
  Add-Content -LiteralPath $LogFile -Value $line
  $old = $Host.UI.RawUI.ForegroundColor
  $Host.UI.RawUI.ForegroundColor = $color
  Write-Host $msg
  $Host.UI.RawUI.ForegroundColor = $old
}
function YearFrom([object]$x){
  if (-not $x) { return $null }
  $m = [regex]::Match([string]$x,'(18|19|20|21)\d{2}')
  if ($m.Success){ [int]$m.Value } else { $null }
}
function Norm([string]$s){
  if (-not $s) { return "" }
  $s = $s.Normalize()
  [regex]::Replace($s, "[^\p{L}\p{Nd}]", "").ToLowerInvariant()
}
function Enc([string]$s){
  $e = [System.Uri]::EscapeDataString([string]$s)
  # ensure '!' is encoded too
  $e = $e.Replace('!','%21')
  return $e
}
function CleanAscii([string]$s){
  if (-not $s) { return "" }
  $n = $s.Normalize([Text.NormalizationForm]::FormD)
  $noMarks = -join ($n.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })
  ([regex]::Replace($noMarks, '[^\w\s]', '')).Trim()
}

# ===== Read CSV =====
try {
  $rows = (Get-Content -LiteralPath $InputCsv -Encoding UTF8) | ConvertFrom-Csv -Delimiter $Delimiter
} catch {
  $rows = Import-Csv -LiteralPath $InputCsv -Delimiter $Delimiter
}
if (-not $rows) { throw "No rows parsed from $InputCsv" }

$base    = $JellyseerrUrl.TrimEnd('/')
$headers = @{ "X-Api-Key" = $ApiKey; "Content-Type" = "application/json" }
$Total   = $rows.Count
$todo    = if ($Limit -gt 0) { [Math]::Min($Limit, $Total) } else { $Total }

Log "Start import | file=$InputCsv | rows=$Total | limit=$todo | strictYear=$StrictYear | deDupe=$DeDupe | dryRun=$($DryRun.IsPresent) | base=$base" ([ConsoleColor]::Cyan)

# ===== HTTP helpers =====
function Seerr-SearchMovie {
  param(
    [string]$Title,
    [Nullable[int]]$Year = $null,
    [int]$MaxRetries = 3,
    [int]$BaseSleepMs = 400
  )
  # Patterns: ASCII-clean first, original next, then with Year
  $patterns = @()
  $ascii = CleanAscii $Title
  if ($ascii -and $ascii -ne $Title) { $patterns += $ascii }
  $patterns += $Title
  if ($Year) { $patterns += @("$Title ($Year)", "$Title $Year") }

  foreach ($p in $patterns) {
    for ($attempt=1; $attempt -le $MaxRetries; $attempt++) {
      $u = "$base/api/v1/search?query=$(Enc $p)"
      try {
        $resp = Invoke-WebRequest -Method GET -Headers $headers -Uri $u -TimeoutSec 20
        $json = $resp.Content | ConvertFrom-Json
        $count = if ($json.results) { $json.results.Count } else { ($json | Measure-Object).Count }
        Log "    search '$p' -> HTTP $([int]$resp.StatusCode), results:$count" ([ConsoleColor]::DarkGray)
        return [pscustomobject]@{ ok=$true; data=$json; http=[int]$resp.StatusCode; query=$p }
      } catch {
        $code = try { [int]$_.Exception.Response.StatusCode } catch { 0 }
        $msg  = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        Log "    search '$p' -> HTTP $code : $msg" ([ConsoleColor]::DarkRed)
        if ($code -in 429,500,502,503,504 -or $code -eq 0) {
          $sleep = [int]([Math]::Min(4000, $BaseSleepMs * [Math]::Pow(2,$attempt-1)))
          Start-Sleep -Milliseconds $sleep
          continue
        }
        break
      }
    }
  }
  return [pscustomobject]@{ ok=$false; data=$null; http=$null; query=$Title }
}

function Seerr-RequestMovie([int]$tmdbId, [switch]$DryRun){
  if ($DryRun) {
    return [pscustomobject]@{ success=$true; http=0; message="dry-run"; raw=$null }
  }
  $body = @{ mediaType="movie"; mediaId=$tmdbId } | ConvertTo-Json
  $u = "$base/api/v1/request"
  try {
    $resp = Invoke-WebRequest -Method POST -Headers $headers -Uri $u -ContentType 'application/json' -Body $body -TimeoutSec 30
    [pscustomobject]@{ success=$true; http=[int]$resp.StatusCode; message="ok"; raw=$resp }
  } catch {
    $code = try { [int]$_.Exception.Response.StatusCode } catch { 0 }
    $msg  = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
    [pscustomobject]@{ success=$false; http=$code; message=$msg; raw=$null }
  }
}

# ===== Process =====
$report = New-Object System.Collections.Generic.List[object]
$seen   = New-Object 'System.Collections.Generic.HashSet[string]'

$idx = 0
foreach ($r in $rows) {
  $idx++
  if ($Limit -gt 0 -and $idx -gt $Limit) { break }

  $pct = [int](($idx / [double]$todo) * 100)
  $title = ($r.$TitleCol).ToString().Trim()
  $year  = YearFrom $r.$YearCol

  Write-Progress -Activity "Importing movies" -Status "[$idx/$todo] $title ($year)" -PercentComplete $pct
  Log "[${idx}/${todo}] SEARCH  '$title' ($year)" ([ConsoleColor]::Yellow)

  if (-not $title) {
    Log " -> skipped (empty title)" ([ConsoleColor]::DarkYellow)
    continue
  }
  if ($StrictYear -and -not $year) {
    Log " -> skipped (missing year, strictYear on)" ([ConsoleColor]::DarkYellow)
    $report.Add([pscustomobject]@{title=$title;year=$null;chosenTitle=$null;chosenYear=$null;tmdbId=$null;status="skipped";detail="missing year";http=$null})
    continue
  }

  # de-dupe
  $key = "$(Norm $title)|$year"
  if ($DeDupe -and $seen.Contains($key)) {
    Log " -> skipped (duplicate)" ([ConsoleColor]::DarkYellow)
    $report.Add([pscustomobject]@{title=$title;year=$year;chosenTitle=$null;chosenYear=$null;tmdbId=$null;status="skipped";detail="duplicate";http=$null})
    continue
  }
  $null = $seen.Add($key)

  # search (encoded + retries + patterns)
  $sr = Seerr-SearchMovie -Title $title -Year $year
  if (-not $sr.ok) {
    Log " -> search_failed (exhausted patterns/retries)" ([ConsoleColor]::Red)
    $report.Add([pscustomobject]@{title=$title;year=$year;chosenTitle=$null;chosenYear=$null;tmdbId=$null;status="search_failed";detail="HTTP error";http=$sr.http})
    Start-Sleep -Milliseconds $DelayMs; continue
  }
  $resp = $sr.data

  # candidates
  $cands = @()
  if ($resp.results) { $cands = $resp.results } else { $cands = $resp }
  $cands = $cands | Where-Object { $_.mediaType -eq "movie" -or $_.type -eq "movie" -or $_.title -or $_.name }
  Log " -> candidates: $($cands.Count)" ([ConsoleColor]::Gray)

  # strict: exact normalized title + same year
  $want = Norm $title
  $best = $null
  foreach ($c in $cands) {
    $ctitle = if ($c.title) { $c.title } else { $c.name }
    $rdate  = if ($c.releaseDate) { $c.releaseDate } else { $c.release_date }
    $cyear  = YearFrom $rdate
    if ((Norm $ctitle) -eq $want -and $cyear -eq $year) { $best = $c; break }
  }
  # fallback 1: exact normalized title (ignore year)
  if (-not $best) {
    $best = $cands | Where-Object {
      $ct = if ($_.title) { $_.title } else { $_.name }
      (Norm $ct) -eq $want
    } | Select-Object -First 1
  }
  # fallback 2: same release year
  if (-not $best) {
    $best = $cands | Where-Object {
      $rd = if ($_.releaseDate) { $_.releaseDate } else { $_.release_date }
      (YearFrom $rd) -eq $year
    } | Select-Object -First 1
  }

  if (-not $best) {
    Log " -> no_match (no exact or year-only match)" ([ConsoleColor]::DarkRed)
    $report.Add([pscustomobject]@{title=$title;year=$year;chosenTitle=$null;chosenYear=$null;tmdbId=$null;status="no_match";detail="no exact/year match";http=$sr.http})
    Start-Sleep -Milliseconds $DelayMs; continue
  }

  $ctitle = if ($best.title) { $best.title } else { $best.name }
  $rdate  = if ($best.releaseDate) { $best.releaseDate } else { $best.release_date }
  $cyear  = YearFrom $rdate
  $tmdbId = if ($best.id) { [int]$best.id } elseif ($best.tmdbId) { [int]$best.tmdbId } else { $null }

  if (-not $tmdbId) {
    Log " -> no_match (no tmdb id on best)" ([ConsoleColor]::DarkRed)
    $report.Add([pscustomobject]@{title=$title;year=$year;chosenTitle=$ctitle;chosenYear=$cyear;tmdbId=$null;status="no_match";detail="no tmdb id";http=$sr.http})
    Start-Sleep -Milliseconds $DelayMs; continue
  }

  Log " -> MATCH tmdb:$tmdbId  '$ctitle' ($cyear)" ([ConsoleColor]::Green)

  # request / dry-run
  $res = Seerr-RequestMovie $tmdbId -DryRun:$DryRun
  if ($res.success) {
    $status = if ($DryRun) { "dryrun" } else { "added" }
    Log " -> $status (http:$($res.http))" ([ConsoleColor]::Green)
    $report.Add([pscustomobject]@{title=$title;year=$year;chosenTitle=$ctitle;chosenYear=$cyear;tmdbId=$tmdbId;status=$status;detail=$res.message;http=$res.http})
  } else {
    Log " -> FAILED (http:$($res.http)) $($res.message)" ([ConsoleColor]::Red)
    $report.Add([pscustomobject]@{title=$title;year=$year;chosenTitle=$ctitle;chosenYear=$cyear;tmdbId=$tmdbId;status="request_failed";detail=$res.message;http=$res.http})
  }

  Start-Sleep -Milliseconds $DelayMs
}

$report | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
Log "Done. Report: $OutCsv | Log: $LogFile" ([ConsoleColor]::Cyan)
Write-Progress -Activity "Importing movies" -Completed
