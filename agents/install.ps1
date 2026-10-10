# Installs a skill agent (MattPocock or JesseVincent) for GitHub Copilot in VS Code: the agent file plus its skills.
#
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/alexlol87/public_ish_projects/main/agents/install.ps1))) MattPocock
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/alexlol87/public_ish_projects/main/agents/install.ps1))) JesseVincent -User
#
# Without -User it installs into the current project's .github\ (agents\<name>.agent.md and agent-skills\<slug>\);
# with -User into ~\.copilot\, for all your projects. Running it again updates the agent and replaces its skills.
# $env:PUBLIC_ISH_PROJECTS_RAW overrides where the files come from. Windows PowerShell 5.1 or PowerShell 7.
param(
    [Parameter(Mandatory = $true)][ValidateSet('MattPocock', 'JesseVincent')][string]$Agent,
    [switch]$User
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$raw = if ($env:PUBLIC_ISH_PROJECTS_RAW) { $env:PUBLIC_ISH_PROJECTS_RAW } else { 'https://raw.githubusercontent.com/alexlol87/public_ish_projects/main' }
$base = if ($User) { Join-Path $HOME '.copilot' } else { '.github' }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())

try {
    # files.txt: <path in the repository> TAB <path under the install folder> TAB <x if executable>
    $list = Join-Path $tmp 'files.txt'
    New-Item -ItemType Directory -Force $tmp | Out-Null
    Invoke-WebRequest "$raw/agents/$Agent/files.txt" -OutFile $list -UseBasicParsing
    foreach ($line in Get-Content $list) {
        if (-not $line.Trim()) { continue }
        $source, $target = $line.Split("`t")[0, 1]
        $out = Join-Path (Join-Path $tmp 'out') $target
        New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
        Invoke-WebRequest "$raw/$source" -OutFile $out -UseBasicParsing
    }

    # Every agent-skills\<slug>\ folder is replaced as a whole, so skills removed upstream don't linger.
    New-Item -ItemType Directory -Force (Join-Path $base 'agents'), (Join-Path $base 'agent-skills') | Out-Null
    foreach ($skills in Get-ChildItem -Directory (Join-Path $tmp 'out/agent-skills')) {
        $installed = Join-Path (Join-Path $base 'agent-skills') $skills.Name
        if (Test-Path $installed) { Remove-Item -Recurse -Force $installed }
        Move-Item $skills.FullName $installed
    }
    Get-ChildItem (Join-Path $tmp 'out/agents') -Filter '*.agent.md' |
        ForEach-Object { Move-Item -Force $_.FullName (Join-Path (Join-Path $base 'agents') $_.Name) }
    Write-Host "Installed ${Agent}: $(Join-Path $base 'agents') and $(Join-Path $base 'agent-skills')"
}
finally {
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
}
