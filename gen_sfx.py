"""生成对讲机音效：按键咔哒声 + 无线电底噪（仅用标准库）"""
import wave, struct, math, random, os

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "sfx")
os.makedirs(OUT, exist_ok=True)

def save(name, samples):
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", max(-32768, min(32767, int(s * 32767)))) for s in samples))
    print(f"生成 {path} ({len(samples)/SR:.2f}s)")

def click(duration=0.06, pitch=180):
    """咔哒声：短促噪声脉冲 + 快速衰减 + 低频"咔"音"""
    n = int(SR * duration)
    out = []
    for i in range(n):
        t = i / SR
        env = math.exp(-t * 55)  # 快速衰减
        noise = random.uniform(-1, 1) * env * 0.55
        tone = math.sin(2 * math.pi * pitch * t) * env * 0.45
        out.append((noise + tone) * 0.6)
    return out

def radio_static(duration=3.0):
    """无线电底噪：白噪声 + 轻微低频嗡嗡 + 偶发爆音，循环用"""
    n = int(SR * duration)
    out = []
    for i in range(n):
        t = i / SR
        noise = random.uniform(-1, 1) * 0.13
        hum = math.sin(2 * math.pi * 50 * t) * 0.05 + math.sin(2 * math.pi * 150 * t) * 0.025
        crackle = random.uniform(-1, 1) * 0.15 if random.random() < 0.0005 else 0
        out.append(noise + hum + crackle)
    return out

save("ptt_down.wav", click(0.07, 165))
save("ptt_up.wav", click(0.05, 260))
save("radio_static.wav", radio_static(3.0))
print("完成")
