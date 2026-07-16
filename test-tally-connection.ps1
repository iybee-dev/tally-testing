# Tally JSON API - Multi-Category Connection Test
# Hosted centrally so Iybee can update it anytime - client always runs the latest version.
#
# Run this on the same computer where TallyPrime is installed and open.
# Requires TallyPrime 7.0 or later (native JSON support).
#
# This script only READS data (Export/Collection requests) - it does not
# create, change, or delete anything in Tally. Safe to run anytime.
#
# Results are written to: .\tally-testing\tally-results.json
# The file is OVERWRITTEN every run - no manual cleanup needed.

$ErrorActionPreference = "Stop"

$outputFolder = "D:\tally-testing"
if (-not (Test-Path "D:\")) {
    Write-Host "D: drive not found - using current folder instead." -ForegroundColor Yellow
    $outputFolder = Join-Path (Get-Location) "tally-testing"
}
$outputFile = Join-Path $outputFolder "tally-results.json"

New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null

function Invoke-TallyApi {
    param(
        [string]$TestName,
        [string]$Id,
        [string]$Type = "Collection"
    )

    $headers = @{
        "content-type" = "application/json"
        "version"      = "1"
        "tallyrequest" = "Export"
        "type"         = $Type
        "id"           = $Id
    }

    $body = @"
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

    $result = [ordered]@{
        test   = $TestName
        id     = $Id
        type   = $Type
        status = "unknown"
    }

    try {
        $response = Invoke-RestMethod -Uri "http://localhost:9000" -Method POST -Headers $headers -Body $body -ContentType "application/json"
        $result.status   = "success"
        $result.response = $response
        Write-Host "[OK]   $TestName" -ForegroundColor Green
    }
    catch {
        $result.status = "failed"
        $result.error  = $_.Exception.Message
        Write-Host "[FAIL] $TestName - $($_.Exception.Message)" -ForegroundColor Red
    }

    return $result
}

Write-Host "Running Tally API tests..." -ForegroundColor Cyan
Write-Host "Results will be saved to: $outputFile`n" -ForegroundColor DarkGray

$allResults = [ordered]@{
    ranAt   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    machine = $env:COMPUTERNAME
    tests   = @()
}

$testPlan = @(
    @{ name = "List of Companies";   id = "List of Companies"; type = "Collection" }
    @{ name = "List of Ledgers";     id = "Ledger";            type = "Collection" }
    @{ name = "List of Groups";      id = "Group";             type = "Collection" }
    @{ name = "List of Stock Items"; id = "StockItem";         type = "Collection" }
    @{ name = "List of Stock Groups";id = "StockGroup";        type = "Collection" }
    @{ name = "Trial Balance";       id = "Trial Balance";     type = "Data" }
)

foreach ($t in $testPlan) {
    $allResults.tests += (Invoke-TallyApi -TestName $t.name -Id $t.id -Type $t.type)
}

$allResults | ConvertTo-Json -Depth 12 | Set-Content -Path $outputFile -Encoding UTF8 -Force

Write-Host "`nAll tests completed." -ForegroundColor Cyan
Write-Host "Results saved to: $outputFile" -ForegroundColor Cyan
Write-Host "Please share this file with your Iybee contact." -ForegroundColor Yellow
