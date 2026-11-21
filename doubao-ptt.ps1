<#
.SYNOPSIS
  豆包对讲机（后台版）：按住热键录音，松开发送，带无线电音效。
.DESCRIPTION
  CDP 直接发空格 keydown/keyup 给豆包（按住空格说话，松手发送），Edge 可完全后台。
  音效：按下 PTT 播按钮音（此时无底噪）；松开后 1 秒播底噪 12 秒（覆盖豆包回答）。

  用法：
    .\doubao-ptt.ps1                  # 默认 F10
    .\doubao-ptt.ps1 -HotKey F9
    .\doubao-ptt.ps1 -NoRadio         # 关闭音效
    .\doubao-ptt.ps1 -TestSound       # 只测试音效，不监听按键（验证声音用）
#>
param(
  [ValidateSet("F9","F10","F11","F12","ScrollLock","Pause")]
  [string]$HotKey = "F10",
  [switch]$NoRadio,
  [switch]$TestSound
)

$ErrorActionPreference = "Stop"
$toolsDir = Join-Path $PSScriptRoot ".tools"
$env:PATH = "$toolsDir\node;$toolsDir\npm-global;$env:PATH"
Add-Type -AssemblyName System.Windows.Forms

$sfxDir    = Join-Path $toolsDir "sfx"
$staticWav = Join-Path $sfxDir "radio_static.wav"
$downWav   = Join-Path $sfxDir "ptt_down.wav"
$upWav     = Join-Path $sfxDir "ptt_up.wav"

function Play-Wav([string]$wav, [switch]$Loop) {
  if ($NoRadio -or -not (Test-Path $wav)) { return }
  $p = New-Object System.Media.SoundPlayer($wav)
  $p.Load()
  if ($Loop) { $p.PlayLooping() } else { $p.Play() }
  return $p
}

function Play-Button([string]$wav) { $null = Play-Wav $wav }

# 底噪播放器（主循环时间戳控制，避开 Timer 回调问题）
$script:staticPlayer = $null
$script:staticStartAt = $null   # 底噪该开始的时刻
$script:staticStopAt = $null    # 底噪该停止的时刻
function Start-Static {
  if ($NoRadio -or $script:staticPlayer) { return }
  $script:staticPlayer = Play-Wav $staticWav -Loop
  Write-Host "  [底噪] 开始" -ForegroundColor DarkGray
}
function Stop-Static {
  if ($script:staticPlayer) { try { $script:staticPlayer.Stop() } catch {} }
  $script:staticPlayer = $null
  $script:staticStartAt = $null
  $script:staticStopAt = $null
}

# ---- 音效测试模式 ----
if ($TestSound) {
  Write-Host "测试按钮音..." -ForegroundColor Yellow
  Play-Button $downWav; Start-Sleep -Milliseconds 500
  Write-Host "测试底噪（3秒）..." -ForegroundColor Yellow
  Start-Static; Start-Sleep -Seconds 3
  Stop-Static
  Write-Host "音效测试完成" -ForegroundColor Green
  exit 0
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KeyWatch { [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey); }
"@
$VK = @{ "F9"=0x78; "F10"=0x79; "F11"=0x7A; "F12"=0x7B; "ScrollLock"=0x91; "Pause"=0x13 }
$hotVk = $VK[$HotKey]

try { (Invoke-WebRequest -Uri "http://127.0.0.1:9222/json/version" -UseBasicParsing -TimeoutSec 3) | Out-Null }
catch { Write-Host "[!] Edge CDP(9222) 未启动" -ForegroundColor Red; exit 1 }

# 启动 CDP daemon
$daemon = Join-Path $toolsDir "cdp-ptt-daemon.mjs"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "$toolsDir\node\node.exe"
$psi.Arguments = "`"$daemon`""
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$np = [System.Diagnostics.Process]::Start($psi)
function Send-Cmd([string]$cmd) { $np.StandardInput.WriteLine($cmd); $np.StandardInput.Flush() }
Start-Sleep -Milliseconds 1200
Send-Cmd "PING"
$ready = $false
for ($i = 0; $i -lt 20; $i++) {
  if ($np.HasExited) { Write-Host "[!] CDP daemon 启动失败" -ForegroundColor Red; exit 1 }
  if (-not $np.StandardOutput.EndOfStream) {
    $reply = $np.StandardOutput.ReadLine()
    if ($reply -match "PONG") { $ready = $true; break }
  }
  Start-Sleep -Milliseconds 100
}
if (-not $ready) { Write-Host "[!] CDP 未就绪" -ForegroundColor Red; $np.Kill(); exit 1 }
Send-Cmd "FOCUS"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " 豆包对讲机已就绪  热键: $HotKey" -ForegroundColor Cyan
Write-Host " Edge 可后台 / 按住说话 / 松开发送" -ForegroundColor Cyan
Write-Host " 退出: Ctrl+C`n" -ForegroundColor Cyan

$script:recording = $false
$stateFile = Join-Path $toolsDir "speak-state.txt"
$wasSpeaking = $false
try {
  while (-not $np.HasExited) {
    $pressed = ([KeyWatch]::GetAsyncKeyState($hotVk) -band 0x8000) -ne 0
    if ($pressed -and -not $script:recording) {
      Stop-Static
      Play-Button $downWav
      Send-Cmd "DOWN"
      $script:recording = $true
      Write-Host "[录音] 开始说话..." -ForegroundColor Yellow
    }
    elseif (-not $pressed -and $script:recording) {
      Play-Button $upWav
      Send-Cmd "UP"
      $script:recording = $false
      Write-Host "[发送] 已发送，等豆包开口`n" -ForegroundColor Green
    }

    # 读豆包朗读状态（daemon 写入），精确跟随语音开关底噪
    if (-not $NoRadio) {
      $speaking = $false
      if (Test-Path $stateFile) { $speaking = ((Get-Content $stateFile -Raw).Trim() -eq '1') }
      if ($speaking -and -not $wasSpeaking) {
        Start-Static
        Write-Host "  [底噪] 豆包开口 -> 开" -ForegroundColor DarkGray
      } elseif (-not $speaking -and $wasSpeaking) {
        Stop-Static
        Write-Host "  [底噪] 豆包说完 -> 关" -ForegroundColor DarkGray
      }
      $wasSpeaking = $speaking
    }

    Start-Sleep -Milliseconds 100
  }
}
finally {
  if ($script:recording) { Send-Cmd "UP" }
  Stop-Static
  $np.Kill()
  Write-Host "已退出。" -ForegroundColor DarkGray
}
