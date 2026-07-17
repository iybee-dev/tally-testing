# Tally JSON API - Cleanup Script
# Finds and deletes all test stock items created by test-tally-connection.ps1
# (items named like API-Test-Item-20260717-143022) and removes them from Tally.
#
# Run this on the same computer where TallyPrime is installed and open.
# Requires TallyPrime 7.0 or later (native JSON support).
#
# Output (overwritten every run):
#   D:\tally-testing\tally-cleanup-results.json
#   D:\tally-testing\tally-cleanup-summary.txt

$ErrorActionPreference = "Stop"

# Company name as it appears exactly in Tally (Gateway of Tally, top of screen)
$companyName = "MURUGU FURNITURE PRIVATE LIMITED 26-27"

$namePrefix = "API-Test-Item-"

$outputFolder = "D:\tally-testing"
if (-not (Test-Path "D:\")) {
    Write-Host "D: drive not found - using current folder instead." -ForegroundColor Yellow
    $outputFolder = Join-Path (Get-Location) "tally-testing"
}
$jsonFile    = Join-Path $outputFolder "tally-cleanup-results.json"
$summaryFile = Join-Path $outputFolder "tally-cleanup-summary.txt"

New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null

function Invoke-TallyApi {
    param(
        [string]$TallyRequest = "Export",
        [string]$Type = "Collection",
        [string]$Id,
        [string]$BodyJson
    )

    $headers = @{
        "version"      = "1"
        "tallyrequest" = $TallyRequest
        "type"         = $Type
        "id"           = $Id
    }

    $urisToTry = @("http://localhost:9000", "http://127.0.0.1:9000")
    $lastError = $null

    foreach ($uri in $urisToTry) {
        try {
            return Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $BodyJson -ContentType "application/json"
        }
        catch {
            $lastError = $_.Exception.Message
        }
    }

    throw $lastError
}

Write-Host "Looking for test stock items starting with '$namePrefix' ...`n" -ForegroundColor Cyan

# ---------------------------------------------------------------
# Step 1: Pull all stock items so we can find the ones to delete
# ---------------------------------------------------------------
$listBody = @"
{
  "static_variables": [
    {
      "type": "String",
      "key": "SVEXPORTFORMAT",
      "name": "",
      "value": "JSONEX"
    }
  ]
}
"@

$results = [ordered]@{
    ranAt       = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    machine     = $env:COMPUTERNAME
    namePrefix  = $namePrefix
    deletions   = @()
}

$namesToDelete = @()

try {
    $listResponse = Invoke-TallyApi -TallyRequest "Export" -Type "Collection" -Id "StockItem" -BodyJson $listBody

    # Tally's JSONEX collection structure can vary slightly by version,
    # so we search the response text itself for matching stock item names.
    $rawText = $listResponse | ConvertTo-Json -Depth 20
    $matches = [regex]::Matches($rawText, [regex]::Escape($namePrefix) + '[0-9\-]+')
    $namesToDelete = $matches.Value | Select-Object -Unique

    Write-Host "Found $($namesToDelete.Count) matching test item(s)." -ForegroundColor Cyan
}
catch {
    Write-Host "Could not read stock item list: $($_.Exception.Message)" -ForegroundColor Red
    $results.listError = $_.Exception.Message
}

# ---------------------------------------------------------------
# Step 2: Delete each matching item
# ---------------------------------------------------------------
foreach ($name in $namesToDelete) {

    $deleteBody = @"
{
  "static_variables": [
    {
      "name": "svMstImportFormat",
      "value": "jsonex"
    },
    {
      "name": "svCurrentCompany",
      "value": "$companyName"
    }
  ],
  "tallymessage": [
    {
      "metadata": {
        "type": "Stock Item",
        "name": "$name",
        "action": "delete"
      },
      "name": "$name"
    }
  ]
}
"@

    $entry = [ordered]@{ name = $name; status = "unknown" }

    try {
        $response = Invoke-TallyApi -TallyRequest "Import" -Type "Data" -Id "All Masters" -BodyJson $deleteBody
        $deletedCount = $response.data.import_result.deleted
        if ($deletedCount -gt 0) {
            $entry.status   = "deleted"
            $entry.response = $response
            Write-Host "[DELETED] $name" -ForegroundColor Green
        }
        else {
            $entry.status   = "failed"
            $entry.response = $response
            $entry.error    = "Tally accepted the request but deleted 0 records - check field format"
            Write-Host "[FAILED]  $name - accepted but nothing was deleted" -ForegroundColor Red
        }
    }
    catch {
        $entry.status = "failed"
        $entry.error  = $_.Exception.Message
        Write-Host "[FAILED]  $name - $($_.Exception.Message)" -ForegroundColor Red
    }

    $results.deletions += $entry
}

if ($namesToDelete.Count -eq 0) {
    Write-Host "Nothing to clean up - no test items found." -ForegroundColor Yellow
}

# ---------------------------------------------------------------
# Save raw results
# ---------------------------------------------------------------
$results | ConvertTo-Json -Depth 12 | Set-Content -Path $jsonFile -Encoding UTF8 -Force

# ---------------------------------------------------------------
# Save readable summary
# ---------------------------------------------------------------
$summaryLines = New-Object System.Collections.Generic.List[string]
$summaryLines.Add("Tally Test Stock Item Cleanup")
$summaryLines.Add("==============================")
$summaryLines.Add("Run on : $($results.ranAt)")
$summaryLines.Add("Machine: $($results.machine)")
$summaryLines.Add("")

if ($namesToDelete.Count -eq 0) {
    $summaryLines.Add("No test items found matching '$namePrefix' - nothing to clean up.")
}
else {
    foreach ($d in $results.deletions) {
        $line = "[{0}] {1}" -f ($d.status.ToUpper()), $d.name
        $summaryLines.Add($line)
        if ($d.status -eq "failed") {
            $summaryLines.Add("        Reason: $($d.error)")
        }
    }
    $deletedCount = ($results.deletions | Where-Object { $_.status -eq "deleted" }).Count
    $summaryLines.Add("")
    $summaryLines.Add("Summary: $deletedCount out of $($namesToDelete.Count) test item(s) deleted.")
}

$summaryLines | Set-Content -Path $summaryFile -Encoding UTF8 -Force

Write-Host "`nCleanup completed." -ForegroundColor Cyan
Write-Host "Summary saved to: $summaryFile" -ForegroundColor Cyan
Write-Host "Full details saved to: $jsonFile" -ForegroundColor Cyan
