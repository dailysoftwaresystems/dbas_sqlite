$ErrorActionPreference = "Stop"

# Check defined Github token
if (-not $env:GITHUB_TOKEN -or [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
    Write-Error "❌ Environment variable GITHUB_TOKEN is not defined."
    exit 1
}

$GitHubToken = $env:GITHUB_TOKEN
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
New-Item -ItemType Directory -Force -Path "$SCRIPT_DIR/../../example/web/libs" | Out-Null

Copy-Item "$OUT_DIR/android/a64/*" -Destination "$SCRIPT_DIR/../../android/src/main/jniLibs/arm64-v8a" -Recurse -Force
Copy-Item "$OUT_DIR/android/armeabi/*" -Destination "$SCRIPT_DIR/../../android/src/main/jniLibs/armeabi-v7a" -Recurse -Force
Copy-Item "$OUT_DIR/android/x86_64/*" -Destination "$SCRIPT_DIR/../../android/src/main/jniLibs/x86_64" -Recurse -Force
Copy-Item "$OUT_DIR/macos/a64/*" -Destination "$SCRIPT_DIR/../../macos/libs/a64" -Recurse -Force
Copy-Item "$OUT_DIR/macos/x86/*" -Destination "$SCRIPT_DIR/../../macos/libs/x86" -Recurse -Force
Copy-Item "$OUT_DIR/windows/*" -Destination "$SCRIPT_DIR/../../windows/libs" -Recurse -Force
Copy-Item "$OUT_DIR/linux/*" -Destination "$SCRIPT_DIR/../../linux/libs" -Recurse -Force
Copy-Item "$OUT_DIR/web/*" -Destination "$SCRIPT_DIR/../../web/libs" -Recurse -Force
Copy-Item "$OUT_DIR/web/*" -Destination "$SCRIPT_DIR/../../example/web/libs" -Recurse -Force

Write-Host "Copying ios binaries..."
Copy-Item "$OUT_DIR/ios/dbas_sqlite.xcframework" -Destination "$SCRIPT_DIR/../../ios" -Recurse -Force

Write-Host "Copying macos binaries..."
Copy-Item "$OUT_DIR/macos/dbas_sqlite.xcframework" -Destination "$SCRIPT_DIR/../../macos" -Recurse -Force

Write-Host "All platform binaries copied successfully."