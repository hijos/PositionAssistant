param(
  [string]$Mode = "release",
  [string]$Name = "持仓助手.apk"
)
$root = Split-Path $PSScriptRoot -Parent
$outDir = Join-Path $root "client\build\app\outputs\flutter-apk"
$src = Join-Path $root "client\build\app\outputs\apk\$Mode\app-$Mode.apk"
if (-not (Test-Path $src)) { $src = Join-Path $outDir "app-$Mode.apk" }
if (-not (Test-Path $src)) { Write-Error "build artifact not found"; exit 1 }
$dst = Join-Path $outDir $Name
foreach ($oldName in @($Name, "app-release.apk", "app-debug.apk") | Select-Object -Unique) {
  $oldPath = Join-Path $outDir $oldName
  if ($oldPath -ne $src -and (Test-Path $oldPath)) { Remove-Item -LiteralPath $oldPath -Force }
}
Move-Item -LiteralPath $src -Destination $dst
$item = Get-Item -LiteralPath $dst
Write-Host "  $($item.FullName)"
Write-Host ("  size: {0:N1} MB" -f ($item.Length / 1MB))
