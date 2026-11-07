#!/usr/bin/env python3
"""Render a vertical (1080x1920) animated fact video with German voice-over.

Usage: python3 render.py scripts/2026-11-07-venus.json
Output: videos/<date>-<slug>.mp4 (+ .png cover, .txt caption)
"""
import json, math, os, random, subprocess, sys, tempfile, wave
from multiprocessing import Pool

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(ROOT, "assets")
VOICE = os.path.join(ASSETS, "voices", "de_DE-thorsten-high.onnx")
W, H, FPS, SR = 1080, 1920, 30, 44100
FONT_BLACK = "/usr/share/fonts/opentype/inter/InterDisplay-Black.otf"
FONT_BOLD = "/usr/share/fonts/opentype/inter/Inter-Bold.otf"

INTRO, GAP, OUTRO = 0.25, 0.30, 1.0


def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# ---------------------------------------------------------------- audio ----

def tts(text, path, length_scale):
    from piper import PiperVoice, SynthesisConfig
    global _voice
    if "_voice" not in globals():
        _voice = PiperVoice.load(VOICE)
    raw = path + ".raw.wav"
    with wave.open(raw, "wb") as wf:
        _voice.synthesize_wav(text, wf, syn_config=SynthesisConfig(
            length_scale=length_scale, noise_scale=0.6, noise_w_scale=0.8))
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", raw, "-ac", "1", "-ar", str(SR),
                    "-f", "f32le", path], check=True)
    a = np.fromfile(path, dtype=np.float32)
    idx = np.where(np.abs(a) > 0.02)[0]  # trim silence
    if len(idx):
        a = a[max(0, idx[0] - 800): idx[-1] + 2000]
    return a


def music_bed(dur, seed):
    """Soft synthesized ambient track: pad chords + pluck arpeggio + gentle kick."""
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n, np.float32)
    bpm = 100
    beat = 60 / bpm
    bar = beat * 4
    progs = [[57, 53, 48, 55], [50, 57, 53, 48], [45, 52, 48, 55]]
    prog = progs[seed % len(progs)]
    midi = lambda m: 440 * 2 ** ((m - 69) / 12)
    nbars = int(dur / bar) + 2
    for b in range(nbars):
        root = prog[b % 4]
        chord = [root, root + (3 if b % 4 in (0, 1) and seed % 2 == 0 else 4), root + 7, root + 12]
        s, e = int(b * bar * SR), min(n, int((b + 1) * bar * SR) + int(0.4 * SR))
        if s >= n:
            break
        tt = t[s:e] - b * bar
        env = np.minimum(1, tt / 0.6) * np.exp(-np.maximum(0, tt - bar) * 6)
        pad = sum(np.sin(2 * np.pi * midi(m) * tt) + 0.3 * np.sin(2 * np.pi * midi(m) * 2.003 * tt) for m in chord)
        out[s:e] += 0.035 * env * pad
        # arpeggio, 8th notes
        for k in range(8):
            ns = s + int(k * beat / 2 * SR)
            ne = min(n, ns + int(0.5 * SR))
            if ns >= n:
                break
            m = chord[[0, 2, 3, 1, 2, 3, 1, 2][k]] + 12
            tk = t[ns:ne] - t[ns]
            out[ns:ne] += 0.05 * np.exp(-tk * 7) * np.sin(2 * np.pi * midi(m) * tk) * (0.8 + 0.2 * rng.random())
        # kick on every beat
        for k in range(4):
            ks = s + int(k * beat * SR)
            ke = min(n, ks + int(0.3 * SR))
            if ks >= n:
                break
            tk = t[ks:ke] - t[ks]
            f = 50 + 70 * np.exp(-tk * 30)
            out[ks:ke] += 0.12 * np.exp(-tk * 12) * np.sin(2 * np.pi * np.cumsum(f) / SR)
    fade = np.minimum(1, np.minimum(t / 1.0, (dur - t) / 1.2)).clip(0, 1)
    return out * fade


def whoosh(seed):
    rng = np.random.default_rng(seed)
    d = 0.45
    n = int(d * SR)
    x = rng.standard_normal(n).astype(np.float32)
    tt = np.arange(n) / n
    cutoff = 0.02 + 0.25 * np.sin(np.pi * tt) ** 2
    y = np.zeros(n, np.float32)
    acc = 0.0
    for i in range(n):  # one-pole lowpass with sweeping cutoff
        acc += cutoff[i] * (x[i] - acc)
        y[i] = acc
    return 0.5 * y * np.sin(np.pi * tt) ** 1.5


def pop_sfx():
    n = int(0.12 * SR)
    tk = np.arange(n) / SR
    f = 600 + 900 * tk / 0.12
    return 0.10 * np.exp(-tk * 30) * np.sin(2 * np.pi * np.cumsum(f) / SR)


def build_audio(script, tmp):
    ls = script.get("length_scale", 0.92)
    clips = []
    for i, sc in enumerate(script["scenes"]):
        clips.append(tts(sc.get("say", sc["text"]), os.path.join(tmp, f"s{i}.f32"), ls))
    starts, t = [], INTRO
    for c in clips:
        starts.append(t)
        t += len(c) / SR + GAP
    dur = t - GAP + OUTRO
    n = int(dur * SR)
    voice = np.zeros(n, np.float32)
    for st, c in zip(starts, clips):
        s = int(st * SR)
        voice[s:s + len(c)] += c
    voice /= max(1e-6, np.abs(voice).max()) / 0.9
    mix = voice + music_bed(dur, script.get("id", 1))[:n]
    w, p = whoosh(7), pop_sfx()
    for i, st in enumerate(starts):
        s = int((st - 0.12) * SR)
        if i > 0 and s >= 0:
            seg = w[: n - s]
            mix[s:s + len(seg)] += seg * 0.35
        ps = int(st * SR)
        seg = p[: n - ps]
        mix[ps:ps + len(seg)] += seg
    path = os.path.join(tmp, "mix.f32")
    (mix / max(1.0, np.abs(mix).max())).astype(np.float32).tofile(path)
    return path, dur, starts, [len(c) / SR for c in clips]


# ------------------------------------------------------------- timing ------

def word_timings(text, start, length):
    words = text.split()
    weights = []
    for w in words:
        wt = len(w.strip(",.!?;:–-")) + 2
        if w[-1] in ",;:–":
            wt += 4
        elif w[-1] in ".!?":
            wt += 7
        weights.append(wt)
    tot = sum(weights)
    out, t = [], start
    for w, wt in zip(words, weights):
        d = length * wt / tot
        out.append((w, t, t + d))
        t += d
    return out


def chunk_words(timed, max_chars=16, max_words=3):
    chunks, cur = [], []
    for item in timed:
        cand = cur + [item]
        txt = " ".join(x[0] for x in cand)
        if cur and (len(txt) > max_chars or len(cand) > max_words or cur[-1][0][-1] in ".,!?:;–"):
            chunks.append(cur)
            cur = [item]
        else:
            cur = cand
    if cur:
        chunks.append(cur)
    return chunks


# ------------------------------------------------------------- visuals -----

def ease_out_back(x, s=1.9):
    x = min(max(x, 0), 1) - 1
    return 1 + (s + 1) * x ** 3 + s * x ** 2


def ease_out(x):
    x = min(max(x, 0), 1)
    return 1 - (1 - x) ** 3


def emoji_image(ch, size):
    import cairosvg
    code = "-".join(f"{ord(c):x}" for c in ch if ord(c) != 0xFE0F)
    path = os.path.join(ASSETS, "twemoji", code + ".svg")
    if not os.path.exists(path):
        path = os.path.join(ASSETS, "twemoji", "-".join(f"{ord(c):x}" for c in ch) + ".svg")
    png = os.path.join(tempfile.gettempdir(), f"emo_{code}_{size}.png")
    if not os.path.exists(png):
        tmp = png + f".{os.getpid()}.tmp"
        cairosvg.svg2png(url=path, write_to=tmp, output_width=size, output_height=size)
        os.replace(tmp, png)
    return Image.open(png).convert("RGBA")


G = {}  # per-worker state


def init_worker(cfg):
    G.update(cfg)
    s = G["script"]
    G["fonts"] = {
        "cap": ImageFont.truetype(FONT_BLACK, 100),
        "num": ImageFont.truetype(FONT_BLACK, 230),
        "numsuf": ImageFont.truetype(FONT_BLACK, 90),
        "label": ImageFont.truetype(FONT_BLACK, 44),
        "title": ImageFont.truetype(FONT_BOLD, 50),
    }
    G["emojis"] = {sc["emoji"]: emoji_image(sc["emoji"], 560) for sc in s["scenes"]}
    acc = hex2rgb(s.get("accent", "#FFD23F"))
    glow = Image.new("L", (900, 900), 0)
    ImageDraw.Draw(glow).ellipse((150, 150, 750, 750), fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(110))
    G["glow"] = glow
    G["glow_rgb"] = Image.new("RGB", (900, 900), acc)
    rng = random.Random(s.get("id", 1))
    G["particles"] = [(rng.random() * W, rng.random() * H, rng.uniform(2, 7), rng.uniform(20, 70),
                       rng.uniform(0, 6.28)) for _ in range(70)]
    sw, sh = W // 5, H // 5
    yy, xx = np.mgrid[0:sh, 0:sw].astype(np.float32)
    G["grid"] = (xx / sw, yy / sh)


def background(t):
    s = G["script"]
    c1, c2 = (np.array(hex2rgb(c), np.float32) for c in s.get("bg", ["#0b1026", "#2b1055"]))
    acc = np.array(hex2rgb(s.get("accent", "#FFD23F")), np.float32)
    xx, yy = G["grid"]
    k = np.clip(yy + 0.08 * np.sin(xx * 3 + t * 0.6), 0, 1)[..., None]
    img = c1 * (1 - k) + c2 * k
    for i, (cx, cy, r, a) in enumerate([(0.2, 0.25, 0.35, 0.22), (0.85, 0.6, 0.4, 0.18), (0.4, 0.9, 0.3, 0.15)]):
        px = cx + 0.12 * math.sin(t * 0.35 + i * 2)
        py = cy + 0.08 * math.cos(t * 0.3 + i)
        d = ((xx - px) ** 2 + ((yy - py) * 1.78) ** 2) / r ** 2
        col = acc if i == 0 else np.array([255, 255, 255], np.float32) * 0.6 + acc * 0.4
        img += (np.exp(-d * 2.5) * a)[..., None] * (col - img) * 0.9
    small = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    return small.resize((W, H), Image.BILINEAR)


def draw_text_center(d, xy, text, font, fill, stroke=10):
    d.text(xy, text, font=font, fill=fill, anchor="mm", stroke_width=stroke, stroke_fill=(10, 10, 20))


def render_frame(fi):
    t = fi / FPS
    s = G["script"]
    acc = hex2rgb(s.get("accent", "#FFD23F"))
    img = background(t)
    d = ImageDraw.Draw(img)

    # drifting particles
    for (x, y, r, sp, ph) in G["particles"]:
        yy = (y - sp * t) % H
        xx = x + 18 * math.sin(t * 0.8 + ph)
        a = 0.35 + 0.35 * math.sin(t * 2 + ph)
        col = tuple(int(255 * a + c * (1 - a) * 0.3) for c in acc)
        d.ellipse((xx - r, yy - r, xx + r, yy + r), fill=col)

    # which scene?
    starts = G["starts"]
    si = 0
    for i, st in enumerate(starts):
        if t >= st - 0.08:
            si = i
    sc = s["scenes"][si]
    ts = t - (starts[si] - 0.08)
    has_num = bool(sc.get("number"))
    cy = 700 if has_num else 800
    base = 430 if has_num else 560

    # glow
    pulse = 0.55 + 0.15 * math.sin(t * 3)
    g = G["glow"].point(lambda v: int(v * pulse))
    img.paste(G["glow_rgb"], (W // 2 - 450, cy - 450), g)

    # burst ring on scene change
    if ts < 0.6:
        rr = 150 + 700 * ease_out(ts / 0.6)
        wdt = max(1, int(18 * (1 - ts / 0.6)))
        d.ellipse((W / 2 - rr, cy - rr, W / 2 + rr, cy + rr), outline=acc, width=wdt)

    # emoji pop + float
    sc_k = ease_out_back(ts / 0.45) * (1 + 0.035 * math.sin(t * 2.4))
    size = max(2, int(base * sc_k))
    em = G["emojis"][sc["emoji"]].resize((size, size), Image.BILINEAR)
    em = em.rotate(6 * math.sin(t * 1.7), resample=Image.BILINEAR, expand=True)
    fy = cy + int(14 * math.sin(t * 2.1))
    img.paste(em, (W // 2 - em.width // 2, fy - em.height // 2), em)

    # counting number
    if has_num:
        num = sc["number"]
        p = ease_out((ts - 0.15) / 1.0)
        val = num["value"] * p
        fmt = f"{val:,.{num.get('decimals', 0)}f}".replace(",", ".")
        txt = num.get("prefix", "") + fmt
        k = ease_out_back((ts - 0.1) / 0.4)
        if k > 0.02:
            f = G["fonts"]["num"]
            draw_text_center(d, (W // 2, 1060), txt, f, acc, 12)
            if num.get("suffix"):
                draw_text_center(d, (W // 2, 1190), num["suffix"], G["fonts"]["numsuf"], (255, 255, 255), 8)

    # top label
    lab = s.get("label", "WUSSTEST DU?")
    f = G["fonts"]["label"]
    tw = d.textlength(lab, font=f)
    d.rounded_rectangle((W / 2 - tw / 2 - 34, 170, W / 2 + tw / 2 + 34, 250), radius=40, fill=acc)
    d.text((W / 2, 210), lab, font=f, fill=(15, 15, 25), anchor="mm")
    d.text((W / 2, 300), f"Fakt #{s.get('id', 1)}", font=G["fonts"]["title"], fill=(255, 255, 255), anchor="mm",
           stroke_width=4, stroke_fill=(10, 10, 20))

    # captions
    cur_chunk = None
    for ch in G["chunks"]:
        if ch[0][1] - 0.05 <= t < ch[-1][2] + 0.25:
            cur_chunk = ch
    if cur_chunk:
        f = G["fonts"]["cap"]
        hl = set(w.lower() for w in s["scenes"][cur_chunk[0][3]].get("highlight", []))
        k = ease_out_back((t - cur_chunk[0][1] + 0.05) / 0.18, 2.5)
        words = [w[0] for w in cur_chunk]
        sp = d.textlength(" ", font=f)
        widths = [d.textlength(w, font=f) for w in words]
        total = sum(widths) + sp * (len(words) - 1)
        lines = [list(range(len(words)))]
        if total > W - 140 and len(words) > 1:
            lines = [list(range(len(words) - 1)), [len(words) - 1]]
        y0 = 1420 - (len(lines) - 1) * 60
        for li, line in enumerate(lines):
            lw = sum(widths[i] for i in line) + sp * (len(line) - 1)
            x = W / 2 - lw / 2
            for i in line:
                w, a, b, _ = cur_chunk[i]
                active = a <= t < b + 0.05
                key = w.strip(",.!?;:–-").lower()
                col = acc if (active or key in hl) else (255, 255, 255)
                if key in hl and not active:
                    col = tuple(min(255, c + 40) for c in acc)
                yoff = -10 if active else 0
                fsz = f
                if k < 0.999:
                    fsz = ImageFont.truetype(FONT_BLACK, max(10, int(100 * (0.7 + 0.3 * k))))
                d.text((x + widths[i] / 2, y0 + li * 120 + yoff), w, font=fsz, fill=col, anchor="mm",
                       stroke_width=11, stroke_fill=(10, 10, 20))
                x += widths[i] + sp

    # progress bar
    prog = min(1, t / G["dur"])
    d.rounded_rectangle((80, 100, W - 80, 112), radius=6, fill=(255, 255, 255, 60) if False else (60, 60, 80))
    d.rounded_rectangle((80, 100, 80 + max(12, (W - 160) * prog), 112), radius=6, fill=acc)

    return img.tobytes()


# ---------------------------------------------------------------- main -----

def main(script_path):
    script = json.load(open(script_path, encoding="utf-8"))
    name = f"{script['date']}-{script['slug']}"
    outdir = os.path.join(ROOT, "videos")
    os.makedirs(outdir, exist_ok=True)
    tmp = tempfile.mkdtemp()
    print("TTS + audio ...", flush=True)
    audio, dur, starts, lens = build_audio(script, tmp)
    timed = []
    for i, (sc, st, ln) in enumerate(zip(script["scenes"], starts, lens)):
        for w, a, b in word_timings(sc["text"], st, ln):
            timed.append((w, a, b, i))
    chunks = []
    for i in range(len(script["scenes"])):
        chunks += chunk_words([x for x in timed if x[3] == i])
    for sc in script["scenes"]:
        emoji_image(sc["emoji"], 560)  # pre-rasterize once
    cfg = dict(script=script, starts=starts, dur=dur, chunks=chunks)
    nframes = int(dur * FPS)
    out = os.path.join(outdir, name + ".mp4")
    print(f"Rendering {nframes} frames ({dur:.1f}s) ...", flush=True)
    ff = subprocess.Popen([
        "ffmpeg", "-y", "-v", "error",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
        "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", audio,
        "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
        "-af", "loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000", "-c:a", "aac", "-b:a", "192k", "-ac", "2", "-ar", "48000",
        "-movflags", "+faststart", "-shortest", out], stdin=subprocess.PIPE)
    with Pool(os.cpu_count(), initializer=init_worker, initargs=(cfg,)) as pool:
        for i, fr in enumerate(pool.imap(render_frame, range(nframes), chunksize=6)):
            ff.stdin.write(fr)
            if i == int(0.6 * FPS):
                Image.frombytes("RGB", (W, H), fr).save(os.path.join(outdir, name + ".png"))
            if i % 150 == 0:
                print(f"  {i}/{nframes}", flush=True)
    ff.stdin.close()
    ff.wait()
    with open(os.path.join(outdir, name + ".txt"), "w", encoding="utf-8") as fh:
        fh.write(script.get("caption", "") + "\n")
    print("done:", out)


if __name__ == "__main__":
    main(sys.argv[1])
