# MSFS 豆包语音导游

把微软模拟飞行（MSFS）里的位置信息喂给 PC 豆包网页版，让豆包生成地理介绍并**语音播报**，支持对讲机式语音追问。完全复用豆包的免费语音能力，不需要 API key、不花钱。

## 它能做什么

- **F9 位置播报**：读取坐标 → 豆包生成口语化地理介绍 → 语音朗读（支持中/英/日等多语言）
- **F10 语音追问**：按住说话、松开发送，像对讲机一样追问，豆包语音回答
- **无线电音效**：PTT 咔哒声 + 底噪，底噪精确跟随豆包朗读（开口响、说完停）
- **完全后台**：Edge 可最小化，不抢 MSFS 焦点

## 原理

核心思路：SimConnect/Little Navmap 读到坐标 → 通过 CDP 把文字/语音送进豆包网页版 → 豆包自带 TTS 朗读。绕开了付费 API，用现成的豆包客户端当"免费 AI 导游"。

语音追问利用豆包的"按住空格说话、松手发送"机制：脚本通过 CDP 直接发空格 keydown/keyup，不依赖窗口焦点。底噪时机通过监控豆包朗读按钮状态（`aria-label="暂停朗读"` = 正在播放）精确控制。

## 快速开始

### 前置条件

1. Windows + Edge 浏览器
2. Node.js（仓库不含运行时，需本机有 `node`）
3. 豆包账号（网页版登录一次即可）

### 步骤

1. 克隆本仓库，进入目录
2. 启动带调试端口的 Edge（用独立 user-data-dir，避免影响日常浏览器）：

   ```powershell
   & "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" `
     --remote-debugging-port=9222 `
     --user-data-dir="$PWD\.tools\edge-cdp-profile" `
     https://www.doubao.com/chat/
   ```

3. 在打开的 Edge 里**登录豆包**，并开启"自动播报"（左侧设置）
4. 双击 `测试音效.bat` 确认能听到咔哒声和底噪
5. 双击 `启动对讲机.bat`，按住 F10 说话测试

### 位置播报

```powershell
.\doubao-guide.ps1 35.6762 139.6503              # 中文介绍东京
.\doubao-guide.ps1 35.6762 139.6503 -Language en # 英语介绍
.\doubao-guide.ps1 48.8566 2.3522 -Extra "低空飞行"
```

`doubao-ptt.ps1` 默认监听 F10，可用 `-HotKey F9` 换成别的键，`-NoRadio` 关闭音效。

## 文件说明

| 文件 | 作用 |
|---|---|
| `doubao-guide.ps1` | 位置播报：坐标 → 豆包 → 朗读 |
| `doubao-ptt.ps1` | 对讲机：热键按住说话、松开发送 |
| `cdp-ptt-daemon.mjs` | CDP 守护进程（脚本自动调用），发送空格按键 + 监控朗读状态 |
| `gen_sfx.py` | 生成无线电音效（标准库 WAV，可自己替换 sfx/ 里的文件） |
| `sfx/` | 音效文件：`ptt_down.wav`、`ptt_up.wav`、`radio_static.wav` |
| `启动对讲机.bat` / `测试音效.bat` | 双击启动的便捷入口 |

## 自定义音效

直接替换 `sfx/` 下的 WAV 文件即可（PCM 16-bit）。`radio_static.wav` 是循环播放的底噪，建议首尾做淡入淡出避免爆音。换文件后重启脚本生效。

## 状态 / 待办

- [ ] 摇杆按钮映射（用厂商软件把两个键映射成 F9/F10）
- [ ] 接入 Little Navmap Web API 自动读实时坐标（`/api/sim/info`）
- [ ] 读取 MSFS 的 `.pln` 飞行计划文件
- [ ] 打包成单 exe（Python 重写 + PyInstaller，环境已就绪）

## License

MIT
