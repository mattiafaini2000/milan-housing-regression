# Build only the static English report using an existing Windows MiKTeX setup.
param([string] $FormatFile = '')
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildRoot = Join-Path $projectRoot '.build/report'
if ($buildRoot -notlike "$projectRoot\*") { throw 'Build directory is outside the project.' }
foreach ($path in @($PSScriptRoot, (Join-Path $projectRoot 'report'), (Join-Path $projectRoot '.build'))) {
    if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Build paths must not be symbolic links: $path"
    }
}
$engine = Get-Command pdflatex -ErrorAction Stop
$extractor = Get-Command pdfimages -ErrorAction Stop
$configRoot = Join-Path $buildRoot 'miktex/config'
$dataRoot = Join-Path $buildRoot 'miktex/data'
$formatRoot = Join-Path $dataRoot 'miktex/data/le/pdftex'
$figureRoot = Join-Path $buildRoot 'figures'
New-Item -ItemType Directory -Path $buildRoot, $configRoot, $formatRoot, $figureRoot -Force | Out-Null

# Copy a prebuilt format instead of regenerating a format in a global cache.
if (-not $FormatFile) {
    $FormatFile = Join-Path $env:LOCALAPPDATA 'MiKTeX/miktex/data/le/pdftex/pdflatex.fmt'
}
if (-not (Test-Path -LiteralPath $FormatFile -PathType Leaf)) {
    throw 'An existing pdflatex.fmt is required. Pass its path with -FormatFile.'
}
Copy-Item -LiteralPath $FormatFile -Destination (Join-Path $formatRoot 'pdflatex.fmt')

$savedEnvironment = @{}
$localEnvironment = @{
    TEMP = $buildRoot
    TMP = $buildRoot
    TMPDIR = $buildRoot
    MIKTEX_USERCONFIG = $configRoot
    MIKTEX_USERDATA = $dataRoot
    MIKTEX_LOG_DIR = $buildRoot
}
try {
    foreach ($name in $localEnvironment.Keys) {
        $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $localEnvironment[$name], 'Process')
    }
    Push-Location -LiteralPath $projectRoot
    try {
        # Exact embedded artwork: opaque map RGB, unused opaque mask, two JPEGs.
        # This excludes the Italian PDF's prose from the English text layer.
        & $extractor.Source -all 'report/report_faini.pdf' (Join-Path $figureRoot 'artwork')
        if ($LASTEXITCODE -ne 0) { throw 'Original report artwork extraction failed.' }
        foreach ($name in @('artwork-000.png', 'artwork-002.jpg', 'artwork-003.jpg')) {
            if (-not (Test-Path -LiteralPath (Join-Path $figureRoot $name) -PathType Leaf)) {
                throw "Expected report artwork is missing: $name"
            }
        }
        foreach ($pass in 1..2) {
            & $engine.Source --disable-installer --disable-write18 --dont-parse-first-line `
                --interaction=nonstopmode --halt-on-error --recorder `
                "--output-directory=$buildRoot" 'report/milan_housing_report_en.tex'
            if ($LASTEXITCODE -ne 0) { throw "Report compilation failed on pass $pass." }
        }
        Copy-Item -LiteralPath (Join-Path $buildRoot 'milan_housing_report_en.pdf') `
            -Destination (Join-Path $projectRoot 'report/milan_housing_report_en.pdf')
    }
    finally { Pop-Location }
}
finally {
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}
