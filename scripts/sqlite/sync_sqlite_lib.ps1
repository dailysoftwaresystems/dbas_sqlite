$ErrorActionPreference = "Stop"

# Check defined Github token
if (-not $env:GITHUB_TOKEN -or [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
    Write-Error "❌ Environment variable GITHUB_TOKEN is not defined."
    exit 1
}

$GitHubToken = $env:GITHUB_TOKEN
$REPO = "dailysoftwaresystems/DBAS.SQLite"
$BRANCH = "main"
$BASE_URL = "https://api.github.com/repos/$REPO/contents/dbas/dist"
$OUT_DIR = "../../dbas_base_app/native_libs/sqlite"

# Files by platform
$FILES = @{
    "android" = @("dbas_sqlite.so")
    "ios"     = @("dbas_sqlite.dylib")
    "macos"   = @("dbas_sqlite.dylib")
    "linux"   = @("dbas_sqlite.so")
    "windows" = @("dbas_sqlite.dll")
    "web"     = @("dbas_sqlite.wasm", "dbas_sqlite.js")
}

# Github token
$headers = @{
    "Authorization" = "token $GitHubToken"
    "Accept"        = "application/vnd.github.v3.raw"
    "User-Agent"    = "PowerShell"
}

Write-Host "Downloading binaries from $REPO (branch: $BRANCH)...`n"

foreach ($platform in $FILES.Keys) {
    $platformPath = Join-Path $OUT_DIR $platform
    New-Item -Path $platformPath -ItemType Directory -Force | Out-Null

    foreach ($file in $FILES[$platform]) {
        $url = "$BASE_URL/$platform/$file`?ref=$BRANCH"
        $dest = Join-Path $platformPath $file

        Write-Host "-> Downloading $url"
        Invoke-WebRequest -Uri $url -Headers $headers -OutFile $dest -UseBasicParsing
    }
}

Write-Host "`nAll binaries downloaded in: $OUT_DIR"

# TODO: Must copy android one to: android\src\main\jniLibs\<all sub directories>
