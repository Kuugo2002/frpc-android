$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$downloads = Join-Path $project '.downloads'
New-Item -ItemType Directory -Force $downloads | Out-Null
$archive = Join-Path $downloads 'frp.tar.gz'
$checks = Join-Path $downloads 'frp_sha256_checksums.txt'
$base = 'https://github.com/fatedier/frp/releases/download/v0.71.1'
Invoke-WebRequest "$base/frp_0.71.1_android_arm64.tar.gz" -OutFile $archive
Invoke-WebRequest "$base/frp_sha256_checksums.txt" -OutFile $checks
$expected = ((Get-Content $checks | Where-Object { $_ -match 'frp_0.71.1_android_arm64.tar.gz$' }) -split '\s+')[0]
if (!$expected -or (Get-FileHash $archive -Algorithm SHA256).Hash -ne $expected) { throw 'frpc SHA256 mismatch' }
tar.exe -xzf $archive -C $downloads
if ($LASTEXITCODE -ne 0) { throw 'Could not unpack frpc' }
Copy-Item (Join-Path $downloads 'frp_0.71.1_android_arm64/frpc') (Join-Path $project 'android/app/src/main/assets/frpc')
Copy-Item (Join-Path $downloads 'frp_0.71.1_android_arm64/LICENSE') (Join-Path $project 'android/app/src/main/assets/FRP-LICENSE')
Write-Output "Verified frpc 0.71.1 Android ARM64: $expected"
