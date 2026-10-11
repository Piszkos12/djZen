# Packs a folder into a zip with standard '/' entry separators.
# (Compress-Archive and ZipFile.CreateFromDirectory in Windows PowerShell 5.1
#  write '\', which non-Windows unzip tools treat as part of the file name.)
param(
  [Parameter(Mandatory = $true)][string]$Source,
  [Parameter(Mandatory = $true)][string]$Destination
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$src = (Resolve-Path $Source).Path.TrimEnd('\')
if (Test-Path $Destination) { Remove-Item $Destination -Force }
$zip = [IO.Compression.ZipFile]::Open($Destination, 'Create')
try {
  Get-ChildItem -Path $src -Recurse -File | ForEach-Object {
    $entry = $_.FullName.Substring($src.Length + 1).Replace('\', '/')
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $entry, 'Optimal')
  }
} finally {
  $zip.Dispose()
}
