# Tally JSON API - Multi-Category Connection Test
# Hosted centrally so Iybee can update it anytime - client always runs the latest version.
#
# Run this on the same computer where TallyPrime is installed and open.
# Requires TallyPrime 7.0 or later (native JSON support).
#
# Tests 1-6 only READ data (Export/Collection) - nothing is changed.
# Test 7 WRITES one new test stock item into Tally, to confirm create/write
# access also works. It uses a unique, clearly-labelled name so it never
# collides with real data and is easy to find and delete afterwards.
#
# Output (both overwritten every run, no manual cleanup needed):
#   D:\tally-testing\tally-results.json     <- full raw data (for Iybee)
#   D:\tally-testing\tally-results-summary.txt  <- easy-to-read summary

$ErrorActionPreference = "Stop"

$outputFolder = "D:\tally-testing"
if (-not (Test-Path "D:\")) {
    Write-Host "D: drive not found - using current folder instead." -ForegroundColor Yellow
    $outputFolder = Join-Path (Get-Location) "tally-testing"
}
$jsonFile    = Join-Path $outputFolder "tally-results.json"
$summaryFile = Join-Path $outputFolder "tally-results-summary.txt"

New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null

function Invoke-TallyApi {
    param(
        [string]$TestName,
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

    $result = [ordered]@{
        test   = $TestName
        id     = $Id
        type   = $Type
        status = "unknown"
    }

    $urisToTry = @("http://localhost:9000", "http://127.0.0.1:9000")
    $lastError = $null

    foreach ($uri in $urisToTry) {
        try {
            $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $BodyJson -ContentType "application/json"

            # For Import requests, only count it a success if Tally actually created/altered something
            if ($TallyRequest -eq "Import") {
                $createdCount = $response.data.import_result.created
                $alteredCount = $response.data.import_result.altered
                if (($createdCount -gt 0) -or ($alteredCount -gt 0)) {
                    $result.status   = "success"
                    $result.response = $response
                    Write-Host "[OK]   $TestName" -ForegroundColor Green
                }
                else {
                    $result.status   = "failed"
                    $result.response = $response
                    $result.error    = "Tally accepted the request but created/altered 0 records - check field format"
                    Write-Host "[FAIL] $TestName - accepted but nothing was created" -ForegroundColor Red
                }
            }
            else {
                $result.status   = "success"
                $result.response = $response
                Write-Host "[OK]   $TestName" -ForegroundColor Green
            }
            return $result
        }
        catch {
            $lastError = $_.Exception.Message
        }
    }

    $result.status = "failed"
    $result.error  = $lastError
    Write-Host "[FAIL] $TestName - $lastError" -ForegroundColor Red
    return $result
}

# Standard body used for all read-only (Export) tests
$readBody = @"
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

Write-Host "Running Tally API tests..." -ForegroundColor Cyan
Write-Host "Results will be saved to:`n  $jsonFile`n  $summaryFile`n" -ForegroundColor DarkGray

$allResults = [ordered]@{
    ranAt   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    machine = $env:COMPUTERNAME
    tests   = @()
}

$readTestPlan = @(
    @{ name = "List of Companies";    id = "List of Companies"; type = "Collection" }
    @{ name = "List of Ledgers";      id = "Ledger";             type = "Collection" }
    @{ name = "List of Groups";       id = "Group";              type = "Collection" }
    @{ name = "List of Stock Items";  id = "StockItem";          type = "Collection" }
    @{ name = "List of Stock Groups"; id = "StockGroup";         type = "Collection" }
    @{ name = "Trial Balance";        id = "Trial Balance";      type = "Data" }
)

foreach ($t in $readTestPlan) {
    $allResults.tests += (Invoke-TallyApi -TestName $t.name -TallyRequest "Export" -Type $t.type -Id $t.id -BodyJson $readBody)
}

# ---------------------------------------------------------------
# Test 7: Create Stock Item (write test)
# Uses a unique name based on the current date/time so repeated
# runs never clash and the test item is easy to spot and remove.
# ---------------------------------------------------------------
$stockItemName = "API-Test-Item-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$createStockItemBody = @"
{
  "body": {
    "data": {
      "tallymessage": [
        {
          "stockitem": {
            "action": "Create",
            "name": { "type": "String", "value": "$stockItemName" },
            "baseunits": { "type": "String", "value": "Nos" }
          }
        }
      ]
    }
  }
}
"@

$allResults.tests += (Invoke-TallyApi -TestName "Create Stock Item ($stockItemName)" -TallyRequest "Import" -Type "Data" -Id "All Masters" -BodyJson $createStockItemBody)

# ---------------------------------------------------------------
# Save full raw results (for Iybee)
# ---------------------------------------------------------------
$allResults | ConvertTo-Json -Depth 12 | Set-Content -Path $jsonFile -Encoding UTF8 -Force

# ---------------------------------------------------------------
# Save a plain, easy-to-read summary (for the client to glance at)
# ---------------------------------------------------------------
$summaryLines = New-Object System.Collections.Generic.List[string]
$summaryLines.Add("Tally API Test Results")
$summaryLines.Add("========================")
$summaryLines.Add("Run on : $($allResults.ranAt)")
$summaryLines.Add("Machine: $($allResults.machine)")
$summaryLines.Add("")

foreach ($t in $allResults.tests) {
    $line = "[{0}] {1}" -f ($t.status.ToUpper()), $t.test
    $summaryLines.Add($line)
    if ($t.status -eq "failed") {
        $summaryLines.Add("        Reason: $($t.error)")
    }
}

$summaryLines.Add("")
$passCount = ($allResults.tests | Where-Object { $_.status -eq "success" }).Count
$totalCount = $allResults.tests.Count
$summaryLines.Add("Summary: $passCount out of $totalCount tests passed.")
$summaryLines.Add("")
$summaryLines.Add("Full technical details are in: tally-results.json (please share this file with Iybee)")

$summaryLines | Set-Content -Path $summaryFile -Encoding UTF8 -Force

Write-Host "`nAll tests completed." -ForegroundColor Cyan
Write-Host "Summary ($passCount/$totalCount passed) saved to: $summaryFile" -ForegroundColor Cyan
Write-Host "Full details saved to: $jsonFile" -ForegroundColor Cyan
Write-Host "Please share both files with your Iybee contact." -ForegroundColor Yellow
