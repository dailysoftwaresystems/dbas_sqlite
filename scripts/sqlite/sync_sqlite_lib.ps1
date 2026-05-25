$ErrorActionPreference = "Stop"

# Verify GitHub CLI is installed
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "❌ GitHub CLI (gh) is not installed. Install from https://cli.github.com/"
    exit 1
}

# Verify the user is authenticated
gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Not authenticated with GitHub. Run 'gh auth login' first."
    exit 1
}

$GitHubToken = (gh auth token).Trim()
if ([string]::IsNullOrWhiteSpace($GitHubToken)) {
    Write-Error "❌ Failed to retrieve GitHub token from gh CLI."
    exit 1
}
$REPO = "dailysoftwaresystems/DBAS.SQLite"
$BASE_URL = "https://api.github.com/repos/$REPO/contents/dbas/dist"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$NativeLibsDir = "$SCRIPT_DIR/../../native_libs"
$OUT_DIR = "$NativeLibsDir/sqlite"

# Github token
$headers = @{
    "Authorization" = "token $GitHubToken"
    "Accept"        = "application/vnd.github.v3.raw"
    "User-Agent"    = "PowerShell"
}

function DownloadRecursive($url, $localPath) {
    Write-Host "Reading: $url into $localPath"
    $items = Invoke-RestMethod -Uri $url -Headers $headers

    foreach ($item in $items) {
        $name = $item.name
        $type = $item.type
        $downloadUrl = $item.download_url
        $nextUrl = $item.url
        $targetPath = Join-Path $localPath $name

        if ($type -eq "file") {
            Write-Host "Downloading $targetPath"
            New-Item -ItemType Directory -Force -Path $localPath | Out-Null
            Invoke-WebRequest -Uri $downloadUrl -OutFile $targetPath -Headers $headers
        } elseif ($type -eq "dir") {
            DownloadRecursive $nextUrl $targetPath
        }
    }
}

Remove-Item "$NativeLibsDir/sqlite/*" -Recurse -Force
New-Item -ItemType Directory -Force -Path $OUT_DIR | Out-Null
DownloadRecursive $BASE_URL $OUT_DIR

Write-Host "All binaries downloaded in: $OUT_DIR, copying binaries to respective platform directories..."

Write-Host "Copying android binaries..."
New-Item -ItemType Directory -Force -Path "$SCRIPT_DIR/../../android/src/main/jniLibs/arm64-v8a" | Out-Null
New-Item -ItemType Directory -Force -Path "$SCRIPT_DIR/../../android/src/main/jniLibs/armeabi-v7a" | Out-Null
New-Item -ItemType Directory -Force -Path "$SCRIPT_DIR/../../android/src/main/jniLibs/x86_64" | Out-Null
New-Item -ItemType Directory -Force -Path "$SCRIPT_DIR/../../macos/libs/a64" | Out-Null
New-Item -ItemType Directory -Force -Path "$SCRIPT_DIR/../../macos/libs/x86" | Out-Null
New-Item -ItemType Directory -Force -Path "$SCRIPT_DIR/../../windows/libs" | Out-Null
New-Item -ItemType Directory -Force -Path "$SCRIPT_DIR/../../linux/libs" | Out-Null
New-Item -ItemType Directory -Force -Path "$SCRIPT_DIR/../../web/libs" | Out-Null

Copy-Item "$OUT_DIR/android/a64/*" -Destination "$SCRIPT_DIR/../../android/src/main/jniLibs/arm64-v8a" -Recurse -Force
Copy-Item "$OUT_DIR/android/armeabi/*" -Destination "$SCRIPT_DIR/../../android/src/main/jniLibs/armeabi-v7a" -Recurse -Force
Copy-Item "$OUT_DIR/android/x86_64/*" -Destination "$SCRIPT_DIR/../../android/src/main/jniLibs/x86_64" -Recurse -Force
Copy-Item "$OUT_DIR/macos/a64/*" -Destination "$SCRIPT_DIR/../../macos/libs/a64" -Recurse -Force
Copy-Item "$OUT_DIR/macos/x86/*" -Destination "$SCRIPT_DIR/../../macos/libs/x86" -Recurse -Force
Copy-Item "$OUT_DIR/windows/*" -Destination "$SCRIPT_DIR/../../windows/libs" -Recurse -Force
Copy-Item "$OUT_DIR/linux/*" -Destination "$SCRIPT_DIR/../../linux/libs" -Recurse -Force
Copy-Item "$OUT_DIR/web/*" -Destination "$SCRIPT_DIR/../../web/libs" -Recurse -Force

# The cross-origin-isolation service worker must also sit at the example's
# web ROOT, not just in web/libs: a service worker only controls its own URL
# path, so to isolate the document (required for SharedArrayBuffer / the
# multi-worker DB pool) it has to be served from "/". Guarded so the sync
# still works against an older dist that predates coi-serviceworker.js.
if (Test-Path "$OUT_DIR/web/coi-serviceworker.js") {
    New-Item -ItemType Directory -Force -Path "$SCRIPT_DIR/../../example/web" | Out-Null
    Copy-Item "$OUT_DIR/web/coi-serviceworker.js" -Destination "$SCRIPT_DIR/../../example/web/" -Force
}

Write-Host "Copying ios binaries..."
New-Item -ItemType Directory -Force -Path "$SCRIPT_DIR/../../ios/dbas_sqlite" | Out-Null
Copy-Item "$OUT_DIR/ios/dbas_sqlite.xcframework" -Destination "$SCRIPT_DIR/../../ios/dbas_sqlite" -Recurse -Force

Write-Host "Copying macos binaries..."
New-Item -ItemType Directory -Force -Path "$SCRIPT_DIR/../../macos/dbas_sqlite" | Out-Null
Copy-Item "$OUT_DIR/macos/dbas_sqlite.xcframework" -Destination "$SCRIPT_DIR/../../macos/dbas_sqlite" -Recurse -Force

# Defensive: fix the upstream `_x86_x64` typo (extra `x`) in xcframework slice names.
$Xcframeworks = @(
    "$SCRIPT_DIR/../../ios/dbas_sqlite/dbas_sqlite.xcframework",
    "$SCRIPT_DIR/../../macos/dbas_sqlite/dbas_sqlite.xcframework"
)
foreach ($fw in $Xcframeworks) {
    Get-ChildItem -Path $fw -Directory -Filter "*_x86_x64*" -ErrorAction SilentlyContinue | ForEach-Object {
        $newName = $_.Name -replace '_x86_x64', '_x86_64'
        Write-Host "Fixing slice name typo: $($_.Name) -> $newName"
        Rename-Item -Path $_.FullName -NewName $newName
    }
}

Write-Host "All platform binaries copied successfully."
