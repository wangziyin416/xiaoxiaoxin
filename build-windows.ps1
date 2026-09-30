$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputDir = Join-Path $projectRoot "dist\windows-x64"
$archivePath = Join-Path $projectRoot "dist\小小信-Windows-x64.zip"

Set-Location $projectRoot

if (Test-Path $outputDir) {
    Remove-Item $outputDir -Recurse -Force
}

if (Test-Path $archivePath) {
    Remove-Item $archivePath -Force
}

dotnet publish "windows\XiaoXiaoXin\XiaoXiaoXin.csproj" `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=false `
    -o $outputDir

Compress-Archive -Path "$outputDir\*" -DestinationPath $archivePath
Write-Host "Windows 安装包已生成：$archivePath"
