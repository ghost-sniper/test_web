#requires -Version 5.1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Test-ZigVersion([string]$Compiler, [string]$RequiredVersion) {
    try {
        $detected = & $Compiler version 2>$null
        return ($LASTEXITCODE -eq 0 -and ($detected -join '').Trim() -ceq $RequiredVersion)
    } catch {
        return $false
    }
}

Push-Location -LiteralPath $PSScriptRoot
try {
    $manifest = 'scripts/zig-toolchain.txt'
    foreach ($file in @('build.zig', 'build.zig.zon', $manifest)) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing project file: $file" }
    }
    $lines = @(Get-Content -LiteralPath $manifest)
    $version = $lines[0].Trim()
    if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid pinned Zig version.' }

    $installed = Get-Command zig -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $compiler = if ($installed) { $installed.Source } else { $null }
    if (-not $compiler -or -not (Test-ZigVersion $compiler $version)) {
        $runtime = [System.Runtime.InteropServices.RuntimeInformation]
        $platformType = [System.Runtime.InteropServices.OSPlatform]
        $os = if ($runtime::IsOSPlatform($platformType::Windows)) { 'windows' }
        elseif ($runtime::IsOSPlatform($platformType::Linux)) { 'linux' }
        elseif ($runtime::IsOSPlatform($platformType::OSX)) { 'macos' }
        else { throw "No automatic download for this OS. Install Zig $version and add it to PATH." }
        $arch = switch ($runtime::OSArchitecture.ToString()) {
            'X64' { 'x86_64' }
            'Arm64' { 'aarch64' }
            'X86' { 'x86' }
            default { throw "No automatic download for this CPU. Install Zig $version and add it to PATH." }
        }
        $platform = "$arch-$os"
        $package = "zig-$platform-$version"
        $suffix = if ($os -eq 'windows') { 'zip' } else { 'tar.xz' }
        $executable = if ($os -eq 'windows') { 'zig.exe' } else { 'zig' }
        $cache = Join-Path $PSScriptRoot '.zig-cache/toolchains'
        $packagePath = Join-Path $cache $package
        $compiler = Join-Path $packagePath $executable

        if (-not (Test-Path -LiteralPath $compiler -PathType Leaf) -or -not (Test-ZigVersion $compiler $version)) {
            $expected = $null
            foreach ($line in $lines) {
                if ($line -cmatch "^$platform\s+([0-9a-f]{64})$") {
                    $expected = $Matches[1]
                    break
                }
            }
            if (-not $expected) { throw "No pinned Zig archive for $platform." }
            if ($os -ne 'windows' -and -not (Get-Command tar -CommandType Application -ErrorAction SilentlyContinue)) {
                throw 'Install tar with xz support to extract the Zig archive.'
            }
            if (Test-Path -LiteralPath $packagePath) { throw "Invalid cached toolchain: $packagePath. Remove it and retry." }

            New-Item -ItemType Directory -Force -Path $cache | Out-Null
            $cache = (Resolve-Path -LiteralPath $cache).ProviderPath
            $stage = (New-Item -ItemType Directory -Path (Join-Path $cache ('.zig-download.' + [guid]::NewGuid().ToString('N')))).FullName
            try {
                $archive = Join-Path $stage "$package.$suffix"
                Write-Host "Downloading Zig $version for $platform..."
                $oldProgress = $ProgressPreference
                try {
                    $ProgressPreference = 'SilentlyContinue'
                    Invoke-WebRequest -UseBasicParsing -TimeoutSec 300 -Uri "https://ziglang.org/download/$version/$package.$suffix" -OutFile $archive
                } finally {
                    $ProgressPreference = $oldProgress
                }
                if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $expected) {
                    throw 'Zig archive SHA-256 mismatch.'
                }
                if ($os -eq 'windows') {
                    Expand-Archive -LiteralPath $archive -DestinationPath $stage
                } else {
                    & tar -xJf $archive -C $stage
                    if ($LASTEXITCODE -ne 0) { throw 'Could not extract the Zig archive.' }
                }
                $extracted = (Resolve-Path -LiteralPath (Join-Path $stage $package)).ProviderPath
                if ([IO.Path]::GetDirectoryName($extracted) -ne $stage) { throw 'Unexpected archive layout.' }
                if (-not (Test-ZigVersion (Join-Path $extracted $executable) $version)) {
                    throw 'Downloaded compiler failed its version check.'
                }
                try {
                    Move-Item -LiteralPath $extracted -Destination $cache
                } catch {
                    if (-not (Test-ZigVersion $compiler $version)) { throw }
                }
            } finally {
                $resolvedStage = (Resolve-Path -LiteralPath $stage -ErrorAction SilentlyContinue)
                if ($resolvedStage -and [IO.Path]::GetDirectoryName($resolvedStage.ProviderPath) -eq $cache) {
                    Remove-Item -LiteralPath $resolvedStage.ProviderPath -Recurse -Force
                }
            }
        }
    }

    Write-Host "Using Zig ${version}: $compiler"
    Write-Host 'Checking project dependencies...'
    & $compiler build --fetch
    if ($LASTEXITCODE -ne 0) { throw "Dependency check failed (exit $LASTEXITCODE). Check the fetch error above." }
    Write-Host 'Building with the default optimization level...'
    & $compiler build
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
