# Packs a folder into a zip with standard '/' entry separators.
# (Compress-Archive and ZipFile.CreateFromDirectory in Windows PowerShell 5.1
#  write '\', which non-Windows unzip tools treat as part of the file name.)
# With -Root, every entry is placed under that top-level folder, so even
# "extract here" into Downloads creates its own folder and djZen.exe never
# lands next to unrelated files (e.g. a planted DLL).
param(
  [Parameter(Mandatory = $true)][string]$Source,
  [Parameter(Mandatory = $true)][string]$Destination,
  [string]$Root = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$src = (Resolve-Path $Source).Path.TrimEnd('\')
$prefix = ''
if ($Root -ne '') { $prefix = $Root.Trim('/', '\') + '/' }
if (Test-Path $Destination) { Remove-Item $Destination -Force }
$zip = [IO.Compression.ZipFile]::Open($Destination, 'Create')
try {
  Get-ChildItem -Path $src -Recurse -File | ForEach-Object {
    $entry = $prefix + $_.FullName.Substring($src.Length + 1).Replace('\', '/')
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $entry, 'Optimal')
  }
} finally {
  $zip.Dispose()
}
