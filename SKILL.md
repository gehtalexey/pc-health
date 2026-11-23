---
name: pc-health
description: One check for everything that makes a Windows PC slow or choked while running Claude Code - RAM, commit memory (page file) and the processor (CPU) - plus a safe cleanup of leftover console windows. Shows the top memory users, the top processor users and long-running leftover processes. Use when the user says the computer is slow, laggy, frozen, out of memory, CPU at 100%, "check the PC", "PC health", or asks to free memory / RAM.
---

# PC Health

A Windows PC that runs several Claude Code sessions gets choked in three different ways: RAM full, commit memory full, or the processor at 100%. This skill checks all three at once, closes the one kind of junk that is safe to close, and says which one is the real limit.

## What to do

Run the bundled script:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME\.claude\skills\pc-health\scripts\pc-health.ps1"
```

From the Bash tool, `$` inside an inline `powershell -Command "..."` gets eaten. For any extra check, write a `.ps1` file to the scratchpad and run it with `-File`.

Then answer in at most 3 plain sentences, leading with which of the three is the limit:
1. **RAM**: the "Freed" line and how many leftover console windows were closed.
2. **Commit memory**: if it is near the limit, the fix is a bigger page file (below), not closing apps.
3. **Processor**: if it is at 90-100%, name the top users from the processor list.

**Always end with one suggestion**: one plain sentence saying what to do next, based on the biggest user of the limit. Examples: "Let the render finish before starting another heavy session", "Close Chrome tabs you are not using", "Nothing to do, the PC is fine". If the fix needs the user's OK (stopping a process, changing settings), ask first.

## What the script does and does not touch

- **Safe:** it only force-closes orphaned `conhost.exe` processes (empty console windows whose program already exited). It never closes a console whose parent is alive, and it protects its own chain of parent processes. Every other section only reads.
- Never extend it to kill other processes without asking the user first. Long-running leftovers are listed for a look; stop one only after the user says so.
- To stop leftover consoles piling up, close Claude Code sessions with `/exit` rather than closing the window.

## Commit memory (page file)

A PC can freeze with plenty of RAM free when commit memory is full. A common cause is a small automatic page file (for example 2 GB). The fix is a fixed, larger page file. This is a system setting, so Claude must not change it. Give the user this line for an admin PowerShell, then a restart (sizes in MB; 16 GB initial / 32 GB max suits a 32 GB machine):

```
$cs = Get-CimInstance Win32_ComputerSystem; Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile=$false}; Get-CimInstance Win32_PageFileSetting | Set-CimInstance -Property @{InitialSize=16384; MaximumSize=32768}
```

## Processor (CPU)

With many parallel Claude Code sessions, the processor is often the real limit, not RAM. Usual causes:

- **Busy sessions.** Only sessions that are working use the processor. Idle sessions cost almost nothing, so closing them does not help.
- **Hooks that run on every tool call.** A slow hook runs once per tool call in every session. A hook that takes 2 seconds, in 3 busy sessions, adds up fast. Time your hooks; merge several small ones into one process.
- **Windows Defender** (`MsMpEng`) scans every file the sessions touch. Claude must not change Defender. If the user wants it lighter, the safer move is a folder exclusion they add themselves in an admin PowerShell, never switching Defender off, e.g. `Add-MpPreference -ExclusionPath "$HOME\projects"`.
- **Local (stdio) MCP servers.** Every session starts its own copy of each one. Ten sessions with two local MCP servers is twenty extra processes. Remote (http) MCP servers cost the PC nothing.
- **Stray long commands.** A leftover `find / -name ...` can scan the disk for hours. The script's "long-running leftovers" list catches these.

## Buying the next PC

For many parallel Claude Code sessions the processor matters more than RAM.
- Avoid low-power "U" laptop chips (name ends in U, e.g. i5-1334U).
- Look for more performance cores: desktop Intel Core i7/i9 or AMD Ryzen 7/9, or laptop "H"/"HX"/"HS" chips.
- 32 GB RAM is enough for most people; keep a fixed page file.
