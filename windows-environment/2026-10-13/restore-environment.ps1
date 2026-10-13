<#
Preview by default. Persistent environment values are written only with -Apply.
Preserve the new Windows defaults, merge validated PATH directories, and restore
only the reviewed software variables below. No software or credentials are installed.
#>
[CmdletBinding()]
param(
    [string]$BackupFile,
    [ValidateSet('All', 'User', 'Machine')][string]$Scope = 'All',
    [string]$MappingsFile,
    [string]$PlanFile,
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
if ([string]::IsNullOrWhiteSpace($BackupFile)) { $BackupFile = Join-Path $PSScriptRoot 'environment-backup.json' }
$BackupFile = [IO.Path]::GetFullPath($BackupFile)
$backup = Get-Content -LiteralPath $BackupFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ($backup.schema_version -ne 1 -or $null -eq $backup.scopes) {
    throw 'Unsupported or invalid environment backup.'
}
$checksumFile = [IO.Path]::ChangeExtension($BackupFile, '.sha256')
if (-not (Test-Path -LiteralPath $checksumFile -PathType Leaf)) {
    throw 'Backup checksum file is missing. Keep environment-backup.json and environment-backup.sha256 together.'
}
$expectedHash = ((Get-Content -LiteralPath $checksumFile -Raw).Trim() -split '\s+')[0]
$actualHash = (Get-FileHash -LiteralPath $BackupFile -Algorithm SHA256).Hash
if ($expectedHash -notmatch '^[0-9a-fA-F]{64}$' -or $expectedHash -ine $actualHash) {
    throw 'Backup integrity check failed. Do not modify the backup; use a separate mappings file.'
}

function Read-Key([string]$TargetScope) {
    $root = [Microsoft.Win32.Registry]::CurrentUser
    $keyPath = 'Environment'
    if ($TargetScope -eq 'Machine') {
        $root = [Microsoft.Win32.Registry]::LocalMachine
        $keyPath = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    }
    $key = $root.OpenSubKey($keyPath, $false)
    if ($null -eq $key) { return @() }
    try {
        foreach ($name in ($key.GetValueNames() | Sort-Object)) {
            if ([string]::IsNullOrEmpty($name)) { continue }
            [pscustomobject]@{
                scope = $TargetScope
                name = $name
                value = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                kind = $key.GetValueKind($name).ToString()
            }
        }
    } finally { $key.Dispose() }
}
function Open-WritableKey([string]$TargetScope) {
    if ($TargetScope -eq 'Machine') {
        return [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment', $true)
    }
    return [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
}
function Save-Json([string]$Path, $Value) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    $parent = [IO.Path]::GetDirectoryName($fullPath)
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    [IO.File]::WriteAllText($fullPath, ($Value | ConvertTo-Json -Depth 12), $utf8)
}

$current = @{ Machine = @(Read-Key 'Machine'); User = @(Read-Key 'User') }
$enabledScopes = @('Machine', 'User')
if ($Scope -ne 'All') { $enabledScopes = @($Scope) }
$currentIndex = @{}
foreach ($targetScope in @('Machine', 'User')) {
    foreach ($item in $current[$targetScope]) { $currentIndex[$targetScope + '|' + $item.name] = $item }
}
$initialState = $current | ConvertTo-Json -Depth 10 -Compress
$events = New-Object 'System.Collections.Generic.List[object]'
$writes = New-Object 'System.Collections.Generic.List[object]'
function Event([string]$TargetScope, [string]$Name, [string]$Action, [string]$Reason, [string]$Value = '') {
    $events.Add([pscustomobject][ordered]@{ scope = $TargetScope; name = $Name; action = $Action; reason = $Reason; value = $Value })
}

$newProfile = [Environment]::GetEnvironmentVariable('USERPROFILE')
$newWindows = [Environment]::GetEnvironmentVariable('SystemRoot')
$mappings = @()
if ($MappingsFile) {
    $mapDocument = Get-Content -LiteralPath $MappingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $mapDocument.prefixes) { throw 'Mappings must have a prefixes array with from/to directory paths.' }
    foreach ($mapping in @($mapDocument.prefixes)) {
        if ([string]$mapping.from -notmatch '^(?:[A-Za-z]:\\|\\\\)' -or [string]$mapping.to -notmatch '^(?:[A-Za-z]:\\|\\\\)' -or
            ([string]$mapping.from).Contains(';') -or ([string]$mapping.to).Contains(';')) {
            throw 'Every mapping must contain absolute directory prefixes without semicolons.'
        }
        $mappings += [pscustomobject]@{ from = ([string]$mapping.from).TrimEnd('\'); to = ([string]$mapping.to).TrimEnd('\') }
    }
}
if ($backup.user_profile -and $newProfile) { $mappings += [pscustomobject]@{ from = ([string]$backup.user_profile).TrimEnd('\'); to = $newProfile.TrimEnd('\') } }
if ($backup.windows_directory -and $newWindows) { $mappings += [pscustomobject]@{ from = ([string]$backup.windows_directory).TrimEnd('\'); to = $newWindows.TrimEnd('\') } }
$mappings = @($mappings | Sort-Object @{ Expression = { $_.from.Length }; Descending = $true })

function Map-Value([string]$Value) {
    foreach ($mapping in $mappings) {
        if ($Value.Equals($mapping.from, [StringComparison]::OrdinalIgnoreCase) -or
            $Value.StartsWith($mapping.from + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return $mapping.to + $Value.Substring($mapping.from.Length)
        }
    }
    return $Value
}
function Expand-Value([string]$Value) {
    $expanded = [Environment]::ExpandEnvironmentVariables($Value)
    return Map-Value $expanded
}
function Normalize-Path([string]$Value) {
    return ([Environment]::ExpandEnvironmentVariables($Value.Trim().Trim('"'))).TrimEnd('\').ToLowerInvariant()
}
function Queue-Write([string]$TargetScope, [string]$Name, [string]$Value, [string]$Kind, [string]$Reason) {
    $prior = $currentIndex[$TargetScope + '|' + $Name]
    if ($null -ne $prior -and [string]$prior.value -ceq $Value -and $prior.kind -eq $Kind) {
        Event $TargetScope $Name 'Keep' 'The persistent value already matches.' $Value
        return
    }
    if ($Value.Length -gt 32766) { throw ('Environment value is too long: ' + $Name) }
    $writes.Add([pscustomobject][ordered]@{ scope = $TargetScope; name = $Name; value = $Value; kind = $Kind; reason = $Reason })
    Event $TargetScope $Name 'Set' $Reason $Value
}

$reviewedNames = @('Classpath', 'JAVA_HOME', 'M2_HOME', 'NODE_HOME', 'NPM_CONFIG_CACHE', 'NPM_CONFIG_PREFIX', 'COREPACK_HOME', 'ENCC_HOME', 'ENCLIENT_HOME')
foreach ($targetScope in $enabledScopes) {
    foreach ($item in @($backup.scopes.$targetScope)) {
        if ($item.name -ieq 'Path') { continue }
        if ($item.sensitive -or $item.name -match '(?i)(api[_-]?key|token|secret|password|credential|^IGCCSVC_DB$)') {
            Event $targetScope $item.name 'Skip' 'Opaque or potentially sensitive value requires separate review.' '[REDACTED]'
            continue
        }
        if ($reviewedNames -notcontains $item.name) {
            Event $targetScope $item.name 'Skip' 'Keep new Windows/driver defaults; this variable is outside the reviewed software list.'
            continue
        }
        if ($item.kind -notin @('String', 'ExpandString')) {
            Event $targetScope $item.name 'Skip' 'Unsupported registry type.'
            continue
        }
        $mapped = Map-Value ([string]$item.value)
        $expanded = [Environment]::ExpandEnvironmentVariables($mapped)
        if ($expanded -match '%[^%]+%' -or $expanded -notmatch '^(?:[A-Za-z]:\\|\\\\)' -or $expanded.Contains(';')) {
            Event $targetScope $item.name 'Skip' 'Unresolved or non-absolute software path needs manual review.' $mapped
            continue
        }
        $expectedType = 'Container'
        if ($item.name -in @('Classpath', 'ENCLIENT_HOME')) { $expectedType = 'Leaf' }
        if (-not (Test-Path -LiteralPath $expanded -PathType $expectedType)) {
            Event $targetScope $item.name 'Skip' 'Target does not exist or is not accessible. Install the software or provide a path mapping first.' $mapped
            continue
        }
        $marker = $null
        if ($item.name -ieq 'NODE_HOME') { $marker = Join-Path $expanded 'node.exe' }
        if ($item.name -ieq 'JAVA_HOME') { $marker = Join-Path $expanded 'bin\java.exe' }
        if ($item.name -ieq 'M2_HOME') { $marker = Join-Path $expanded 'bin\mvn.cmd' }
        if ($marker -and -not (Test-Path -LiteralPath $marker -PathType Leaf)) {
            Event $targetScope $item.name 'Skip' 'The software executable was not found under the mapped home directory.' $mapped
            continue
        }
        Queue-Write $targetScope $item.name $mapped $item.kind 'Restore a reviewed software variable after checking its target.'
    }
}

$knownPaths = @{}
$pathAdditions = @{ Machine = New-Object 'System.Collections.Generic.List[string]'; User = New-Object 'System.Collections.Generic.List[string]' }
foreach ($targetScope in @('Machine', 'User')) {
    $prior = $currentIndex[$targetScope + '|Path']
    if ($null -ne $prior) {
        foreach ($entry in ([string]$prior.value).Split(';')) {
            if (-not [string]::IsNullOrWhiteSpace($entry)) { $knownPaths[(Normalize-Path $entry)] = $true }
        }
    }
}
function Add-PathCandidate([string]$TargetScope, [string]$Raw, [string]$Reason, [switch]$AlreadyResolved) {
    $expanded = $Raw.Trim().Trim('"')
    if (-not $AlreadyResolved) { $expanded = Expand-Value $expanded }
    if ($TargetScope -notin $enabledScopes) {
        Event $TargetScope 'Path entry' 'Skip' 'This target scope was not selected.' $Raw
        return
    }
    if ([string]::IsNullOrWhiteSpace($expanded)) { return }
    if ($expanded -match '%[^%]+%' -or $expanded -notmatch '^(?:[A-Za-z]:\\|\\\\)' -or $expanded -match '^[A-Za-z]:\\?$') {
        Event $TargetScope 'Path entry' 'Skip' 'Relative path, drive root, or unresolved reference.' $Raw
        return
    }
    if ($expanded -match '(?i)\\(?:venv|\.venv)\\Scripts(?:\\|$)' -or $expanded -match '(?i)\.(exe|cmd|bat|com)$') {
        Event $TargetScope 'Path entry' 'Skip' 'Project virtual environment or executable file does not belong in the global PATH.' $Raw
        return
    }
    if (-not (Test-Path -LiteralPath $expanded -PathType Container)) {
        Event $TargetScope 'Path entry' 'Skip' 'Directory does not exist or is not accessible.' $expanded
        return
    }
    $normalized = Normalize-Path $expanded
    if ($knownPaths.ContainsKey($normalized)) { return }
    $knownPaths[$normalized] = $true
    $pathAdditions[$TargetScope].Add($expanded.TrimEnd('\'))
    Event $TargetScope 'Path entry' 'Add' $Reason $expanded
}

if ('Machine' -in $enabledScopes) {
    foreach ($suffix in @('System32', '', 'System32\Wbem', 'System32\WindowsPowerShell\v1.0', 'System32\OpenSSH')) {
        $essential = $newWindows
        if ($suffix) { $essential = Join-Path $newWindows $suffix }
        Add-PathCandidate 'Machine' $essential 'Ensure standard Windows tool directories are retained.' -AlreadyResolved
    }
}
foreach ($sourceScope in $enabledScopes) {
    $savedPath = @($backup.scopes.$sourceScope | Where-Object { $_.name -ieq 'Path' })
    if ($savedPath.Count -ne 1) { continue }
    foreach ($raw in ([string]$savedPath[0].value).Split(';')) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $expanded = Expand-Value $raw.Trim().Trim('"')
        if ($newWindows -and ($expanded.Equals($newWindows, [StringComparison]::OrdinalIgnoreCase) -or
            $expanded.StartsWith($newWindows.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase))) {
            Event $sourceScope 'Path entry' 'Skip' 'Windows and system-profile paths belong to the new system defaults.' $raw
            continue
        }
        $targetScope = $sourceScope
        $reason = 'Merge a validated directory without replacing the current PATH.'
        if ($newProfile -and $expanded.StartsWith($newProfile.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
            $targetScope = 'User'
            $reason = 'Store a personal-profile directory in the user PATH.'
        }
        Add-PathCandidate $targetScope $expanded $reason -AlreadyResolved
    }
}
foreach ($targetScope in $enabledScopes) {
    if ($pathAdditions[$targetScope].Count -eq 0) { continue }
    $prior = $currentIndex[$targetScope + '|Path']
    $value = ''
    $kind = 'ExpandString'
    if ($null -ne $prior) {
        if ($prior.kind -notin @('String', 'ExpandString')) { throw 'Current PATH has an unsupported registry type.' }
        $value = [string]$prior.value
        $kind = $prior.kind
    }
    if ($value.Length -gt 0 -and -not $value.EndsWith(';')) { $value += ';' }
    $value += ($pathAdditions[$targetScope] -join ';')
    Queue-Write $targetScope 'Path' $value $kind 'Preserve the current PATH and append checked directories.'
}

$plan = [ordered]@{
    generated_at = [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(8)).ToString('o')
    source_backup_sha256 = $actualHash.ToLowerInvariant()
    source_backup_date = $backup.captured_at
    requested_scope = $Scope
    mode = $(if ($Apply) { 'Apply requested' } else { 'Preview only: no environment changes' })
    new_user_profile = $newProfile
    new_windows_directory = $newWindows
    write_count = $writes.Count
    writes = @($writes.ToArray())
    decisions = @($events.ToArray())
}
if ($PlanFile) { Save-Json $PlanFile $plan }
Write-Output ('Mode: ' + $plan.mode)
Write-Output ('Planned persistent writes: ' + $writes.Count)
foreach ($item in $writes) { Write-Output ('  ' + $item.scope + ': ' + $item.name + ' (' + $item.reason + ')') }
Write-Output ('Skipped items: ' + @($events | Where-Object { $_.action -eq 'Skip' }).Count)
if (-not $Apply) {
    Write-Output 'No environment variables were modified. Inspect the plan before using -Apply.'
    return
}
if ($writes.Count -eq 0) { Write-Output 'Nothing to change.'; return }
if (@($writes | Where-Object { $_.scope -eq 'Machine' }).Count -gt 0) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Machine writes require an elevated terminal under the intended user account. Preview mode does not require elevation.'
    }
}
$latest = @{ Machine = @(Read-Key 'Machine'); User = @(Read-Key 'User') }
if (($latest | ConvertTo-Json -Depth 10 -Compress) -cne $initialState) {
    throw 'The persistent environment changed during planning. Run the preview again before applying.'
}
$historyDirectory = Join-Path $PSScriptRoot ('restore-history\' + [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(8)).ToString('yyyyMMdd-HHmmss-fff'))
Save-Json (Join-Path $historyDirectory 'before.json') ([ordered]@{ captured_at = $plan.generated_at; user_profile = $newProfile; scopes = $current })
Save-Json (Join-Path $historyDirectory 'plan.json') $plan
$changed = New-Object 'System.Collections.Generic.List[object]'
try {
    foreach ($item in $writes) {
        $key = Open-WritableKey $item.scope
        if ($null -eq $key) { throw ('Cannot open registry environment key: ' + $item.scope) }
        try {
            $key.SetValue($item.name, $item.value, [Microsoft.Win32.RegistryValueKind]$item.kind)
            $changed.Add($item)
        } finally { $key.Dispose() }
    }
} catch {
    $restoreFailed = $false
    foreach ($item in $changed) {
        try {
            $key = Open-WritableKey $item.scope
            try {
                $prior = $currentIndex[$item.scope + '|' + $item.name]
                if ($null -ne $prior) { $key.SetValue($item.name, $prior.value, [Microsoft.Win32.RegistryValueKind]$prior.kind) }
                else { $key.DeleteValue($item.name, $false) }
            } finally { if ($null -ne $key) { $key.Dispose() } }
        } catch { $restoreFailed = $true }
    }
    if ($restoreFailed) { throw ('Apply failed and rollback needs attention. Original values are saved in: ' + $historyDirectory) }
    throw ('Apply failed; changes made by this run were rolled back. Original values are saved in: ' + $historyDirectory)
}
try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class EnvironmentRestoreBroadcast {
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam,
        string lParam, uint flags, uint timeout, out UIntPtr result);
}
'@
    $result = [UIntPtr]::Zero
    [void][EnvironmentRestoreBroadcast]::SendMessageTimeout([IntPtr]0xffff, 0x001a, [UIntPtr]::Zero, 'Environment', 2, 3000, [ref]$result)
} catch { Write-Warning 'Environment notification could not be sent. Sign out and sign in before using the restored environment.' }
Write-Output ('Restored persistent variables: ' + $changed.Count)
Write-Output ('Pre-change backup: ' + $historyDirectory)
Write-Output 'Close and reopen terminals and applications, or sign out and sign in, to load the new environment.'
