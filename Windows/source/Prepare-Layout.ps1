[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'advanced_main_layout.cpp')
)

$ErrorActionPreference = 'Stop'
$inputPath = Join-Path $PSScriptRoot 'advanced_main.cpp'
$script:text = [IO.File]::ReadAllText($inputPath)

function Replace-Required([string]$From, [string]$To) {
    if (-not $script:text.Contains($From)) {
        throw "Required UI layout source fragment was not found: $From"
    }
    $script:text = $script:text.Replace($From, $To)
}

# Version/title patch for the generated build source.
Replace-Required 'ihatemeetings 1.5' 'ihatemeetings 1.5.1'

# Give the injected Advanced controls their own vertical band and add breathing room
# above the original dialog controls.
Replace-Required 'wr.bottom-wr.top+34' 'wr.bottom-wr.top+48'
Replace-Required 'pt.y+28' 'pt.y+38'
Replace-Required '8,7,116,18' '10,8,138,20'
Replace-Required '130,5,72,22' '156,6,92,24'

# Expand and reflow the Advanced preset editor. These replacements are deliberately
# exact: if the source layout changes later, the build fails instead of silently
# generating an unverified geometry.
Replace-Required '10,12,54,20' '16,14,54,22'
Replace-Required '66,8,110,150' '76,10,150,170'
Replace-Required '10,43,70,20' '16,52,72,22'
Replace-Required '82,40,394,23' '94,48,530,26'
Replace-Required '482,40,72,23' '636,48,108,26'
Replace-Required '10,76,58,20' '16,92,62,22'
Replace-Required '70,72,105,120' '84,88,132,140'
Replace-Required '190,76,62,20' '238,92,66,22'
Replace-Required '254,72,120,120' '308,88,152,140'
Replace-Required '390,76,66,20' '484,92,70,22'
Replace-Required '462,72,92,23' '560,88,184,26'
Replace-Required '10,108,100,20' '16,132,110,22'
Replace-Required '112,104,286,23' '132,128,426,26'
Replace-Required '408,108,76,20' '576,132,80,22'
Replace-Required '482,104,72,23' '662,128,82,26'
Replace-Required '10,139,145,25' '16,170,160,30'
Replace-Required '162,139,165,25' '184,170,184,30'
Replace-Required '10,172,544,150' '16,210,728,190'
Replace-Required '10,329,544,36' '16,410,728,48'
Replace-Required '370,369,88,27' '536,478,98,30'
Replace-Required '466,369,88,27' '646,478,98,30'
Replace-Required '580,445,win,nullptr' '780,570,win,nullptr'

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($OutputPath, $script:text, $utf8NoBom)
Write-Host "Prepared expanded Windows UI source: $OutputPath"
