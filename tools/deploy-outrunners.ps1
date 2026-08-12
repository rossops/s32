[CmdletBinding()]
param(
    [string]$MisterHost = $env:S32_MISTER_HOST,
    [string]$MraPath,
    [switch]$SkipMra
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $MraPath) {
    $MraPath = Join-Path $repoRoot "mra\OutRunners (World).mra"
}

& (Join-Path $PSScriptRoot "deploy-mister.ps1") `
    -MisterHost $MisterHost `
    -Revision "s32OutRunners" `
    -CoreName "s32OutRunners" `
    -MraPath $MraPath `
    -SkipMra:$SkipMra
