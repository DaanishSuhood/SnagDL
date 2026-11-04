# Builds SnagDL for release:
#   .\publish.ps1                 -> artifacts\publish\SnagDL.exe (compiled with Ahk2Exe, no AutoHotkey install needed)
#                                    artifacts\installer\SnagDL-Setup-<version>.exe (Inno Setup installer)
#   .\publish.ps1 -SkipInstaller  -> only the .exe
# Either way it also writes artifacts\SHA256SUMS.txt, to publish with the release.
# The version comes from the ;@Ahk2Exe-SetVersion line in SnagDL.ahk, so the exe and the installer always agree.
param(
    [switch]$SkipInstaller
)
$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'SnagDL.ahk'
$publishDir = Join-Path $PSScriptRoot 'artifacts\publish'
$exe = Join-Path $publishDir 'SnagDL.exe'

$ahk2exe = @(
    (Join-Path $env:ProgramFiles 'AutoHotkey\Compiler\Ahk2Exe.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\Compiler\Ahk2Exe.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ahk2exe) {
    throw 'Ahk2Exe was not found. Install AutoHotkey v2 with: winget install --id AutoHotkey.AutoHotkey -e'
}
# The 64-bit v2 interpreter that the exe is built on; the tools Get Tools fetches are 64-bit too.
$base = Join-Path (Split-Path (Split-Path $ahk2exe)) 'v2\AutoHotkey64.exe'
if (-not (Test-Path $base)) { throw "AutoHotkey v2 (64-bit) was not found at $base." }

$match = Select-String -LiteralPath $source -Pattern '^;@Ahk2Exe-SetVersion\s+(\S+)' | Select-Object -First 1
if (-not $match) { throw 'SnagDL.ahk has no ;@Ahk2Exe-SetVersion line.' }
$version = $match.Matches[0].Groups[1].Value

if (Test-Path $publishDir) { Remove-Item $publishDir -Recurse -Force }
New-Item -ItemType Directory -Path $publishDir | Out-Null

# Ahk2Exe is a GUI program, so PowerShell would not wait for it on its own.
$p = Start-Process -FilePath $ahk2exe -Wait -PassThru -ArgumentList @(
    '/in', "`"$source`"", '/out', "`"$exe`"", '/base', "`"$base`"", '/silent', 'verbose'
)
if ($p.ExitCode -ne 0 -or -not (Test-Path $exe)) { throw "Compiling SnagDL.exe failed (exit code $($p.ExitCode))." }

if (-not $SkipInstaller) {
    $iscc = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $iscc) {
        throw 'Inno Setup 6 was not found. Install it with: winget install --id JRSoftware.InnoSetup -e (or use -SkipInstaller).'
    }

    & $iscc /Q "/DAppVersion=$version" (Join-Path $PSScriptRoot 'installer\SnagDL.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Building the installer failed.' }
    $installer = Join-Path $PSScriptRoot "artifacts\installer\SnagDL-Setup-$version.exe"
}

$artifacts = Join-Path $PSScriptRoot 'artifacts'
# Only what this run built: artifacts\installer may still hold installers from earlier versions.
$files = @(Get-Item $exe) + @(if (-not $SkipInstaller) { Get-Item $installer })

# Releases aren't code-signed, so publish checksums people can compare against
# (sha256sum format: check with `sha256sum -c SHA256SUMS.txt`, or compare with Get-FileHash).
$checksums = Join-Path $artifacts 'SHA256SUMS.txt'
$lines = $files | ForEach-Object { "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $($_.Name)" }
# LF line endings: sha256sum on Linux, macOS and Git Bash treats a CR as part of the file name.
[IO.File]::WriteAllText($checksums, (($lines -join "`n") + "`n"))
$lines

$files |
    Format-Table @{ n = 'File'; e = { $_.FullName.Substring($PSScriptRoot.Length + 1) } },
                 @{ n = 'Size (MB)'; e = { [math]::Round($_.Length / 1MB, 1) } }
