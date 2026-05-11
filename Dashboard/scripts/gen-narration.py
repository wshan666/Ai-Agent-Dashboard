"""gen-narration.py — text → TTS audio via edge-tts Python API
Usage:
  python scripts/gen-narration.py <text-file.txt> <output.mp3>
  python scripts/gen-narration.py --text "<text>" <output.mp3>
Sentences separated by | for timing control.
"""
import sys, os, asyncio, subprocess, tempfile


async def gen(text: str, out_path: str):
    import edge_tts

    sentences = [s.strip() for s in text.split("|") if s.strip()]
    if not sentences:
        print("ERROR: No text provided")
        sys.exit(1)

    voice = "zh-CN-XiaoxiaoNeural"
    rate = "+10%"
    parts = []

    with tempfile.TemporaryDirectory(prefix="tts_") as tmp_dir:
        for i, sent in enumerate(sentences):
            tmp = os.path.join(tmp_dir, f"part_{i:03d}.mp3")
            try:
                communicate = edge_tts.Communicate(sent, voice, rate=rate)
                await communicate.save(tmp)
            except Exception as e:
                print(f"  TTS error on sentence {i}: {e}")
                continue
            if os.path.exists(tmp) and os.path.getsize(tmp) > 0:
                parts.append(tmp)
                print(f"  [{i+1}/{len(sentences)}] Generated {os.path.getsize(tmp)} bytes")
            else:
                print(f"  [{i+1}/{len(sentences)}] FAILED: empty output")

        if not parts:
            print("ERROR: No audio generated")
            sys.exit(1)

        concat_file = os.path.join(tmp_dir, "concat.txt")
        with open(concat_file, "w", encoding="utf-8") as f:
            for p in parts:
                f.write(f"file '{os.path.abspath(p).replace(chr(92), '/')}'\n")

        subprocess.run([
            "ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", concat_file,
            "-c", "copy", out_path
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        print(f"Done: {out_path} ({os.path.getsize(out_path)} bytes)")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print('Usage: python scripts/gen-narration.py <text-file.txt> <output.mp3>')
        print('       python scripts/gen-narration.py --text "<text>" <output.mp3>')
        sys.exit(1)

    if sys.argv[1] == "--text":
        text = sys.argv[2]
        out_path = sys.argv[3]
    else:
        with open(sys.argv[1], "r", encoding="utf-8") as f:
            text = f.read().strip()
        out_path = sys.argv[2]

    asyncio.run(gen(text, out_path))
