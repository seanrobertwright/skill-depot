# Skill Depot — project-scoped skill manager for Claude Code
# PowerShell port of skill-depot.sh. Mirrors the bash CLI exactly.
#
# Usage:
#   .\skill-depot.ps1 add <skill-name>
#   .\skill-depot.ps1 add <github-url>[#subdir]
#   .\skill-depot.ps1 list
#   .\skill-depot.ps1 remove <skill-name>
#   .\skill-depot.ps1 help
#   .\skill-depot.ps1 --version

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AllArgs
)

$ErrorActionPreference = 'Stop'

# PowerShell's -File mode consumes `--` as "end of parameter parsing", which
# mangles `--version` / `--help` if bound positionally. Collect everything and
# dispatch manually so `-v`, `--version`, `help`, `add`, etc. all behave the same.
$AllArgs = @($AllArgs)  # force array
$Command = if ($AllArgs.Count -ge 1) { [string]$AllArgs[0] } else { '' }
# The CLI takes at most one arg after the command, so direct index is enough.
# (Avoids PS's array-slice-scalarizes-to-string trap on typed [string[]] slices.)
$Arg1    = if ($AllArgs.Count -ge 2) { [string]$AllArgs[1] } else { '' }

$Version       = '0.1.0'
$SkillsDir     = '.claude/skills'
$ScriptDir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$RegistryFile  = Join-Path $ScriptDir 'registry.yaml'
$NamePattern   = '^[a-zA-Z0-9_-]+$'

function Show-Usage {
    @"
skill-depot v$Version — project-scoped skill manager for Claude Code

Usage:
  skill-depot add <skill-name>      Install skill from registry
  skill-depot add <github-url>      Install skill from GitHub URL
  skill-depot list                  List installed skills
  skill-depot remove <skill-name>   Remove an installed skill
  skill-depot help                  Show this help
  skill-depot --version             Show version

Skills install into .claude/skills/ relative to the current directory.
"@
}

function Test-SkillName {
    param([string]$Name)
    if ($Name -notmatch $NamePattern) {
        Write-Error "invalid skill name '$Name'. Names must contain only letters, numbers, hyphens, and underscores."
    }
}

function Get-SkillDescription {
    param([string]$SkillMdPath)
    if (-not (Test-Path -LiteralPath $SkillMdPath)) { return '' }
    # Match first top-level `description:` line (ignore nested/indented)
    $line = Select-String -Path $SkillMdPath -Pattern '^description:' -List | Select-Object -First 1
    if (-not $line) { return '' }
    return ($line.Line -replace '^description:\s*', '').Trim()
}

function Invoke-List {
    if (-not (Test-Path -LiteralPath $SkillsDir)) {
        Write-Host "No skills installed ($SkillsDir/ does not exist)."
        return
    }

    $skills = Get-ChildItem -LiteralPath $SkillsDir -Directory -ErrorAction SilentlyContinue
    if (-not $skills) {
        Write-Host "No skills installed in $SkillsDir/."
        return
    }

    Write-Host "Installed skills ($SkillsDir/):"
    foreach ($s in $skills) {
        $desc = Get-SkillDescription (Join-Path $s.FullName 'SKILL.md')
        if ($desc) {
            '{0}  {1,-20} {2}' -f '', $s.Name, $desc | Write-Host
        } else {
            Write-Host "  $($s.Name)"
        }
    }
}

function Invoke-Remove {
    param([string]$Name)
    if (-not $Name) {
        Write-Host 'Usage: skill-depot remove <skill-name>'
        exit 1
    }
    Test-SkillName $Name

    $target = Join-Path $SkillsDir $Name
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        Write-Error "skill '$Name' is not installed in $SkillsDir/."
    }

    Remove-Item -LiteralPath $target -Recurse -Force
    Write-Host "Removed skill '$Name' from $SkillsDir/."

    # Clean up empty .claude/skills/ directory
    if ((Test-Path -LiteralPath $SkillsDir) -and
        -not (Get-ChildItem -LiteralPath $SkillsDir -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $SkillsDir -Force
    }
}

function Resolve-RegistryEntry {
    param([string]$Name)
    if (-not (Test-Path -LiteralPath $RegistryFile)) {
        Write-Error "registry file not found at $RegistryFile"
    }
    # Match same shape as bash: `^  <name>:` — 2-space indent, exact name
    $match = Select-String -Path $RegistryFile -Pattern "^  $([regex]::Escape($Name)):" -List |
             Select-Object -First 1
    if (-not $match) { return $null }
    return ($match.Line -replace '^\s*[^:]+:\s*', '').Trim()
}

function Split-UrlAndSubdir {
    param([string]$Url)
    if ($Url.Contains('#')) {
        $parts  = $Url.Split('#', 2)
        return @{ Url = $parts[0]; Subdir = $parts[1] }
    }
    return @{ Url = $Url; Subdir = '' }
}

function Test-SafeSubdir {
    param([string]$Subdir, [string]$RepoRoot)

    # Reject dangerous syntax early — mirrors the bash case statement
    if ($Subdir.StartsWith('/') -or
        $Subdir -eq '.' -or $Subdir -eq '..' -or
        $Subdir.StartsWith('./') -or $Subdir.StartsWith('../') -or
        $Subdir -match '/\./' -or $Subdir -match '/\.\./' -or
        $Subdir -match '//' -or
        $Subdir.EndsWith('/.') -or $Subdir.EndsWith('/..')) {
        return $false
    }

    # Canonicalize and ensure it stays under the repo root
    $candidate = Join-Path $RepoRoot $Subdir
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
        return $false
    }
    $resolvedCandidate = (Resolve-Path -LiteralPath $candidate).Path
    $resolvedRoot      = (Resolve-Path -LiteralPath $RepoRoot).Path
    return $resolvedCandidate.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)
}

function Invoke-Add {
    param([string]$InputArg)
    if (-not $InputArg) {
        Write-Host 'Usage: skill-depot add <skill-name|github-url>'
        exit 1
    }

    $url = ''; $name = ''; $subdir = ''

    if ($InputArg -match '^https?://' -or $InputArg -match '^git@') {
        # Direct URL
        $parsed = Split-UrlAndSubdir $InputArg
        $url    = $parsed.Url
        $subdir = $parsed.Subdir
        if ($subdir) {
            $name = Split-Path -Leaf $subdir
        } else {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($url)
        }
    } else {
        # Short name — registry lookup
        $name = $InputArg
        Test-SkillName $name
        $entry = Resolve-RegistryEntry $name
        if (-not $entry) {
            Write-Host "Error: skill '$name' not found in registry."
            Write-Host 'Try: skill-depot add <github-url> to install directly.'
            exit 1
        }
        $parsed = Split-UrlAndSubdir $entry
        $url    = $parsed.Url
        $subdir = $parsed.Subdir
    }

    Test-SkillName $name

    $target = Join-Path $SkillsDir $name

    # Idempotent
    if (Test-Path -LiteralPath $target -PathType Container) {
        Write-Host "Skill '$name' is already installed at $target/."
        Write-Host "To reinstall, remove it first: skill-depot remove $name"
        return
    }

    New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null

    $tmp           = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ([Guid]::NewGuid())) -Force
    $stagingParent = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ([Guid]::NewGuid())) -Force
    $stagedTarget  = Join-Path $stagingParent.FullName $name
    $repoPath      = Join-Path $tmp.FullName 'repo'

    try {
        Write-Host "Installing skill '$name'..."

        # Clone
        $env:GIT_TERMINAL_PROMPT = '0'
        & git clone --depth 1 --quiet $url $repoPath
        if ($LASTEXITCODE -ne 0) {
            Write-Error "failed to clone $url"
        }

        # Extract
        if ($subdir) {
            if (-not (Test-SafeSubdir -Subdir $subdir -RepoRoot $repoPath)) {
                Write-Error "invalid or missing subdirectory '$subdir' in $url"
            }
            $source = Join-Path $repoPath $subdir
            Copy-Item -LiteralPath $source -Destination $stagedTarget -Recurse
        } else {
            New-Item -ItemType Directory -Path $stagedTarget -Force | Out-Null
            Get-ChildItem -LiteralPath $repoPath -Force |
                Where-Object { $_.Name -ne '.git' } |
                ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $stagedTarget -Recurse -Force }
        }

        Move-Item -LiteralPath $stagedTarget -Destination $target

        # Verify SKILL.md
        if (-not (Test-Path -LiteralPath (Join-Path $target 'SKILL.md'))) {
            Write-Host "Warning: $target/SKILL.md not found. Claude Code requires SKILL.md to load skills."
        }

        Write-Host "Installed skill '$name' to $target/."
    }
    finally {
        Remove-Item -LiteralPath $tmp.FullName           -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stagingParent.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Note: single-dash flags like -v / -h are unreliable in PowerShell's -File mode
# (PS's arg parser tries to bind them as parameters). Prefer `help` / `version`
# or the double-dash forms `--help` / `--version`.
switch ($Command) {
    'add'        { Invoke-Add    $Arg1 }
    'list'       { Invoke-List }
    'remove'     { Invoke-Remove $Arg1 }
    'help'       { Show-Usage }
    '--help'     { Show-Usage }
    'version'    { "skill-depot $Version" }
    '--version'  { "skill-depot $Version" }
    default      { Show-Usage; exit 1 }
}
