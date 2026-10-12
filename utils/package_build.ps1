$ErrorActionPreference = "Stop"

$distDir = "C:\Users\Rio\AppData\Local\Temp\antigravity\CallOfDiddy_Dist"
if (Test-Path $distDir) {
    Remove-Item -Recurse -Force $distDir
}
New-Item -ItemType Directory -Path $distDir -Force | Out-Null

Write-Host "Copying build files..."
Copy-Item "build\Call Of Diddy.exe" -Destination "$distDir\" -Force
Copy-Item "build\Call Of Diddy.pck" -Destination "$distDir\" -Force
Copy-Item "steam_appid.txt" -Destination "$distDir\" -Force
Copy-Item "addons\godotsteam\win64\steam_api64.dll" -Destination "$distDir\" -Force
Copy-Item "addons\godotsteam\win64\libgodotsteam.windows.template_debug.x86_64.dll" -Destination "$distDir\" -Force
Copy-Item "addons\godotsteam\win64\libgodotsteam.windows.template_release.x86_64.dll" -Destination "$distDir\" -Force

$zipPath = "E:\game\fps\build\CallOfDiddy_Steam_Multiplayer.zip"
if (Test-Path $zipPath) {
    Remove-Item -Force $zipPath
}

Write-Host "Creating clean zip package..."
Compress-Archive -Path "$distDir\*" -DestinationPath $zipPath -Force
Write-Host "Created $zipPath successfully!"
Remove-Item -Recurse -Force $distDir
