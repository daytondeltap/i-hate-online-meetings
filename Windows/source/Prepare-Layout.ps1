[CmdletBinding()]
param([string]$OutputPath = (Join-Path $PSScriptRoot 'advanced_main_layout.cpp'))
$ErrorActionPreference = 'Stop'
Copy-Item (Join-Path $PSScriptRoot 'advanced_main.cpp') $OutputPath -Force
Write-Host "Prepared Windows UI source: $OutputPath"
