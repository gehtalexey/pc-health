# pc-health.ps1 - checks memory, commit memory and processor; clears leftover console windows.
# Safe: only closes orphaned conhost.exe processes (empty leftover terminal windows).

function Get-MemSnapshot {
  $os    = Get-CimInstance Win32_OperatingSystem
  $total = [math]::Round($os.TotalVisibleMemorySize/1MB,1)
  $free  = [math]::Round($os.FreePhysicalMemory/1MB,1)
  $used  = [math]::Round($total-$free,1)
  $pct   = [math]::Round(($used/$total)*100,0)
  return [PSCustomObject]@{ Total=$total; Used=$used; Free=$free; Pct=$pct }
}

$before = Get-MemSnapshot
Write-Output "==== BEFORE ===="
Write-Output ("Total RAM: {0} GB" -f $before.Total)
Write-Output ("In use:    {0} GB ({1}%)" -f $before.Used,$before.Pct)
Write-Output ("Free:      {0} GB" -f $before.Free)

# ---- Clean the junk: ONLY orphaned leftover console windows ----
# A conhost.exe is "orphaned" when the program that owned it has already exited.
# An ACTIVE terminal/Claude Code session has a conhost with a LIVE parent — we must
# NEVER kill those, or we shut down the running session. So: only kill a conhost
# whose parent process is no longer alive. Also protect this script's own ancestry.

# Build the set of currently-alive process IDs.
$aliveIds = @{}
foreach ($p in Get-Process -ErrorAction SilentlyContinue) { $aliveIds[[int]$p.Id] = $true }

# Walk up from this script's own process so we never kill our own console.
$protectedIds = @{}
$walk = $PID
for ($i = 0; $i -lt 20 -and $walk; $i++) {
  $protectedIds[[int]$walk] = $true
  $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $walk" -ErrorAction SilentlyContinue
  if (-not $proc) { break }
  $walk = [int]$proc.ParentProcessId
}

$conBefore = (Get-Process conhost -ErrorAction SilentlyContinue).Count
$killed = 0
foreach ($con in Get-CimInstance Win32_Process -Filter "Name = 'conhost.exe'" -ErrorAction SilentlyContinue) {
  $cid = [int]$con.ProcessId
  $ppid = [int]$con.ParentProcessId
  if ($protectedIds.ContainsKey($cid)) { continue }   # our own session — leave it
  if ($aliveIds.ContainsKey($ppid))   { continue }   # parent alive = active window, leave it
  # Parent is gone — this is a true leftover. Close it.
  Stop-Process -Id $cid -Force -ErrorAction SilentlyContinue
  $killed++
}
Start-Sleep -Seconds 2
$conAfter = (Get-Process conhost -ErrorAction SilentlyContinue).Count

Write-Output ""
Write-Output "==== CLEANUP ===="
Write-Output ("Leftover console windows closed: {0}" -f $killed)
Write-Output ("(Active session windows left untouched.)")

$after = Get-MemSnapshot
Write-Output ""
Write-Output "==== AFTER ===="
Write-Output ("In use:    {0} GB ({1}%)" -f $after.Used,$after.Pct)
Write-Output ("Free:      {0} GB" -f $after.Free)
Write-Output ("Freed:     {0} GB" -f [math]::Round($after.Free - $before.Free,2))

Write-Output ""
Write-Output "==== TOP 10 MEMORY USERS (apps you have open) ===="
Get-Process | Group-Object -Property ProcessName | ForEach-Object {
  [PSCustomObject]@{
    Name  = $_.Name
    GB    = [math]::Round((($_.Group | Measure-Object WorkingSet64 -Sum).Sum)/1GB,2)
    Count = $_.Count
  }
} | Sort-Object GB -Descending | Select-Object -First 10 | Format-Table -AutoSize

# ==== COMMIT MEMORY (read-only) ====
Write-Output ""
Write-Output "==== COMMIT MEMORY ===="
$osc = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
if ($osc) {
  $commitLimitGB = $osc.TotalVirtualMemorySize / 1MB
  $commitUsedGB  = ($osc.TotalVirtualMemorySize - $osc.FreeVirtualMemory) / 1MB
  $commitPct     = [math]::Round(($commitUsedGB / $commitLimitGB) * 100, 0)
  Write-Output ("Commit: {0} of {1} GB ({2}%)" -f [math]::Round($commitUsedGB,1), [math]::Round($commitLimitGB,1), $commitPct)
  if ($commitPct -ge 85) {
    Write-Output "WARNING: commit memory near the limit - the fix is a bigger page file, not closing apps."
  }
} else {
  Write-Output "Could not read commit memory."
}

# ==== PROCESSOR (read-only) ====
Write-Output ""
Write-Output "==== PROCESSOR ===="
$cpus = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
$chipName = ""
if ($cpus) { $chipName = [string](($cpus | Select-Object -First 1).Name) }
$logicalCores = 0
if ($cpus) { $logicalCores = [int](($cpus | Measure-Object NumberOfLogicalProcessors -Sum).Sum) }
if (-not $logicalCores) { $logicalCores = [int]$env:NUMBER_OF_PROCESSORS }
if (-not $logicalCores) { $logicalCores = 1 }
Write-Output ("Chip: {0}" -f $chipName.Trim())
Write-Output ("Logical cores: {0}" -f $logicalCores)

$loadSamples = @()
for ($i = 0; $i -lt 5; $i++) {
  $cpuLoad = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Measure-Object LoadPercentage -Average).Average
  if ($null -ne $cpuLoad) { $loadSamples += [math]::Round([double]$cpuLoad, 0) }
  if ($i -lt 4) { Start-Sleep -Seconds 1 }
}
if ($loadSamples.Count -gt 0) {
  $cpuAvg = [math]::Round((($loadSamples | Measure-Object -Average).Average), 0)
  Write-Output ("Samples (%): {0}" -f ($loadSamples -join ", "))
  Write-Output ("Average load: {0}%" -f $cpuAvg)
  if ($cpuAvg -ge 90) { Write-Output "Processor is the limit right now." }
} else {
  Write-Output "Could not read processor load."
}

# ==== TOP 10 PROCESSOR USERS (read-only) ====
Write-Output ""
Write-Output "==== TOP 10 PROCESSOR USERS ===="
$cpuCounter = Get-Counter '\Process(*)\% Processor Time' -ErrorAction SilentlyContinue
$cpuSamples = @()
if ($cpuCounter) { $cpuSamples = @($cpuCounter.CounterSamples) }
$cpuTop = $cpuSamples |
  Where-Object { $_.InstanceName -ne '_total' -and $_.InstanceName -ne 'idle' } |
  ForEach-Object {
    [PSCustomObject]@{ Name = ($_.InstanceName -replace '#\d+$', ''); Value = $_.CookedValue }
  } |
  Group-Object Name |
  ForEach-Object {
    [PSCustomObject]@{
      Name  = $_.Name
      Pct   = [math]::Round((($_.Group | Measure-Object Value -Sum).Sum) / $logicalCores, 1)
      Count = $_.Count
    }
  } |
  Sort-Object Pct -Descending |
  Select-Object -First 10
if ($cpuTop) {
  $cpuTop | Format-Table -AutoSize
} else {
  Write-Output "No processor data returned."
}

# ==== LONG-RUNNING LEFTOVERS (look, do not kill) ====
# This section only lists. It never stops a process.
Write-Output ""
Write-Output "==== LONG-RUNNING LEFTOVERS (look, do not kill) ===="
$oldCutoff = (Get-Date).AddMinutes(-60)
$watchNames = @('find.exe', 'pytest.exe', 'python.exe', 'node.exe', 'codex.exe')
$leftovers = @()
foreach ($wp in (Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $watchNames -contains $_.Name })) {
  if ($wp.CreationDate -and $wp.CreationDate -lt $oldCutoff) {
    $cmdLine = ""
    if ($wp.CommandLine) { $cmdLine = $wp.CommandLine.Substring(0, [math]::Min(150, $wp.CommandLine.Length)) }
    $leftovers += [PSCustomObject]@{
      Started = $wp.CreationDate.ToString('yyyy-MM-dd HH:mm')
      PID     = $wp.ProcessId
      Name    = $wp.Name
      Command = $cmdLine
    }
  }
}
if ($leftovers.Count -gt 0) {
  $leftovers | Format-Table -AutoSize -Wrap
} else {
  Write-Output "None."
}
