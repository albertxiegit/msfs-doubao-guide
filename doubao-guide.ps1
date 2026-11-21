<#
.SYNOPSIS
  把 MSFS 坐标喂给 PC 豆包网页版，自动生成口语化地理介绍并朗读。
.DESCRIPTION
  依赖：已启动的 Edge CDP(9222) 会话且已登录豆包、agent-browser。
  用法：
    .\doubao-guide.ps1 48.8566 2.3522
    .\doubao-guide.ps1 48.8566 2.3522 -Language en
    .\doubao-guide.ps1 48.8566 2.3522 -Language ja -Extra "低空飞行"
#>
param(
  [Parameter(Mandatory=$true)][double]$Lat,
  [Parameter(Mandatory=$true)][double]$Lon,
  [ValidateSet("zh","en","ja","ko","fr","de","es")]
  [string]$Language = "zh",
  [string]$Extra = "",
  [switch]$NoSpeak
)

$ErrorActionPreference = "Stop"
$toolsDir = Join-Path $PSScriptRoot ".tools"
$env:PATH = "$toolsDir\node;$toolsDir\npm-global;$env:PATH"

function Get-CdpStatus {
  try {
    (Invoke-WebRequest -Uri "http://127.0.0.1:9222/json/version" -UseBasicParsing -TimeoutSec 3) | Out-Null
    return $true
  } catch { return $false }
}

function Ensure-Browser {
  if (-not (Get-CdpStatus)) {
    $edge = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    $profile = Join-Path $toolsDir "edge-cdp-profile"
    Start-Process $edge -ArgumentList "--remote-debugging-port=9222","--user-data-dir=`"$profile`"","--no-first-run","--new-window","https://www.doubao.com/chat/"
    Start-Sleep -Seconds 8
    if (-not (Get-CdpStatus)) { throw "Edge CDP 启动失败" }
  }
  agent-browser connect 9222 2>&1 | Out-Null
  $url = agent-browser get url 2>&1
  if ($url -notmatch "doubao\.com") {
    agent-browser open "https://www.doubao.com/chat/" 2>&1 | Out-Null
    Start-Sleep -Seconds 5
    Write-Host "请在打开的 Edge 窗口中登录豆包（若尚未登录），然后重新运行本脚本。" -ForegroundColor Yellow
  }
}

function Enable-AutoSpeak {
  $snap = agent-browser snapshot -i 2>&1
  if ($snap -match "开启自动播报") {
    $ref = ([regex]::Match($snap, 'button "开启自动播报" \[ref=(e\d+)\]')).Groups[1].Value
    if ($ref) {
      agent-browser click "@$ref" 2>&1 | Out-Null
      Write-Host "[OK] 已开启豆包自动朗读" -ForegroundColor Green
      return
    }
  }
  Write-Host "[i] 自动朗读已开启或按钮未找到，跳过" -ForegroundColor DarkGray
}

Ensure-Browser
Enable-AutoSpeak

$latDir = if ($Lat -ge 0) { "N" } else { "S" }
$lonDir = if ($Lon -ge 0) { "E" } else { "W" }
$coordText = "${latDir}$([Math]::Abs($Lat)), ${lonDir}$([Math]::Abs($Lon))"  # 如 N48.8566, E2.3522

$prompt = switch ($Language) {
  "zh" { "请用中文介绍坐标 $coordText 附近的地理：具体地名、河流、道路、周边小地名和地形特征，口语化导游风格，150字以内。" }
  "en" { "Introduce the geography around $coordText in English: specific place names, rivers, roads, nearby small localities and terrain features. Conversational tour-guide style, under 150 words." }
  "ja" { "座標 $coordText 周辺の地理を日本語で紹介してください：具体的な地名、川、道路、周辺の小さな集落と地形。会話調のガイド風で150文字以内。" }
  "ko" { "좌표 $coordText 주변의 지리를 한국어로 소개해 주세요: 구체적인 지명, 강, 도로, 주변 작은 지역과 지형. 대화형 가이드 스타일로 150자 이내." }
  "fr" { "Présentez en français la géographie autour de $coordText : noms de lieux, rivières, routes, petites localités et relief. Style guide conversationnel, moins de 150 mots." }
  "de" { "Beschreibe auf Deutsch die Geografie um $coordText : konkrete Ortsnamen, Flüsse, Straßen, kleine Ortschaften und Gelände. Umgangssprachlicher Guide-Stil, unter 150 Wörter." }
  "es" { "Presenta en español la geografía alrededor de $coordText : nombres de lugares, ríos, carreteras, pequeñas localidades y terreno. Estilo de guía conversacional, menos de 150 palabras." }
}
if ($Extra) { $prompt += " Context: $Extra" }

# 记录发送前的回答数量，用于准确抓取"新"回答
$beforeCount = 0
try {
  $cnt = agent-browser eval "document.querySelectorAll('[data-testid=audio_play_button]').length" 2>&1
  if ($cnt -match '^\d+$') { $beforeCount = [int]$cnt }
} catch {}

# 点击输入框并填入
agent-browser click "[contenteditable=true].tiptap" 2>&1 | Out-Null
agent-browser fill "[contenteditable=true].tiptap" $prompt 2>&1 | Out-Null
Start-Sleep -Milliseconds 400
agent-browser press Enter 2>&1 | Out-Null
Write-Host "[OK] 已发送坐标给豆包，等待回答..." -ForegroundColor Cyan

# 轮询等待回答完成（最长 60 秒）：检测停止按钮消失且出现新文本
$answer = ""
for ($i = 0; $i -lt 60; $i++) {
  Start-Sleep -Seconds 1
  $state = agent-browser eval "(()=>{const btns=[...document.querySelectorAll('button')].map(b=>b.getAttribute('data-testid')||'');const streaming=btns.some(t=>/stop|cancel|pause/i.test(t));const txt=[...document.querySelectorAll('[class*=markdown],[class*=message-content],[data-testid*=message]')].map(e=>e.innerText).filter(t=>t&&t.length>20);return JSON.stringify({streaming,last:txt.slice(-1)[0]||''})})()" 2>&1
  try {
    $obj = $state | ConvertFrom-Json
    if (-not $obj.streaming -and $obj.last.Length -gt 30) {
      $answer = $obj.last
      break
    }
  } catch {}
}
if (-not $answer) {
  # 回退：按"朗读按钮"数量定位新增回答（audio_play_button 每条 AI 回答都有一个，中英文通用）
  $expr = "(()=>{const btns=document.querySelectorAll('[data-testid=audio_play_button]');let b=btns[$beforeCount]||btns[btns.length-1];if(!b)return '';let n=b;for(let i=0;i<8&&n;i++){if(n.innerText&&n.innerText.length>40)return n.innerText.trim();n=n.parentElement}return ''})()"
  $answer = agent-browser eval $expr 2>&1
}

Write-Host "`n===== 豆包回答 =====" -ForegroundColor Yellow
Write-Host $answer
Write-Host "====================`n" -ForegroundColor Yellow
if (-not $NoSpeak) {
  Write-Host "[i] 豆包自动朗读已开启，语音应正在播放（如未播放，检查系统音量或豆包音量图标）" -ForegroundColor DarkGray
}
