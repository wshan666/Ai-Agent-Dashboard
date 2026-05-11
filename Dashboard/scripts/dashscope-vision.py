#!/usr/bin/env python3
"""DashScope Qwen-VL vision chat — supports [IMG_DATA] blocks, image URLs, and local paths."""
import sys, json, urllib.request, base64, re, os, io

# Force UTF-8 output on Windows
if sys.platform == 'win32':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

API_KEY = os.environ.get('DASHSCOPE_API_KEY', '').strip()
API_URL = 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions'
MODEL = 'qwen-vl-max'

if not API_KEY:
    print('DASHSCOPE_API_KEY is not configured', file=sys.stderr)
    sys.exit(2)

prompt = sys.stdin.read()

# Build message content
content = []

# Parse embedded [IMG_DATA]...[/IMG_DATA] blocks (from server.js buildChatPrompt)
img_data_re = re.compile(r'\[IMG_DATA\](.*?)\[/IMG_DATA\]', re.DOTALL)
img_blocks = img_data_re.findall(prompt)
clean_prompt = img_data_re.sub('', prompt).strip()

# Parse IMAGE_N: data:... format
embedded_images = []
for block in img_blocks:
    for m in re.finditer(r'IMAGE_\d+:\s*(data:\w+/[\w.+-]+;base64,[A-Za-z0-9+/=]+)', block):
        embedded_images.append(m.group(1))

# Fallback: find image URLs in prompt
image_urls = list(set(re.findall(
    r'https?://[\d.]+:?\d*/uploads/[\w.-]+\.(?:jpe?g|png|gif|webp|bmp)',
    prompt, re.IGNORECASE
)))

# Fallback: find local file paths
local_paths = list(set(re.findall(
    r'(?:[A-Z]:[/\\]|[/\\])[\w./\\-]+\.(?:jpe?g|png|gif|webp|bmp)',
    prompt, re.IGNORECASE
)))

# Add text (use cleaned prompt if we had embedded images, otherwise full prompt)
text = clean_prompt if embedded_images else prompt
content.append({"type": "text", "text": text})

# Add embedded images first (from server)
for img_url in embedded_images:
    content.append({
        "type": "image_url",
        "image_url": {"url": img_url}
    })

# Add URL images
seen = set()
for url in image_urls:
    if url in seen:
        continue
    seen.add(url)
    try:
        req = urllib.request.Request(url)
        img_data = urllib.request.urlopen(req, timeout=10).read()
        if len(img_data) < 64:
            continue
        b64 = base64.b64encode(img_data).decode('ascii')
        ext = url.rsplit('.', 1)[-1].lower().split('?')[0]
        mime = f'image/{ext}' if ext in ('png', 'gif', 'webp', 'bmp') else 'image/jpeg'
        content.append({
            "type": "image_url",
            "image_url": {"url": f"data:{mime};base64,{b64}"}
        })
    except Exception as e:
        content.append({
            "type": "text",
            "text": f"\n[无法下载图片 {url}: {e}]"
        })

# Add local file images
for lpath in local_paths:
    lpath_norm = os.path.normpath(lpath)
    if lpath_norm in seen or not os.path.isfile(lpath_norm):
        continue
    seen.add(lpath_norm)
    try:
        with open(lpath_norm, 'rb') as f:
            img_data = f.read()
        if len(img_data) < 64:
            continue
        b64 = base64.b64encode(img_data).decode('ascii')
        ext = lpath_norm.rsplit('.', 1)[-1].lower().split('?')[0]
        mime = f'image/{ext}' if ext in ('png', 'gif', 'webp', 'bmp') else 'image/jpeg'
        content.append({
            "type": "image_url",
            "image_url": {"url": f"data:{mime};base64,{b64}"}
        })
    except Exception as e:
        content.append({
            "type": "text",
            "text": f"\n[无法读取图片 {lpath}: {e}]"
        })

# Single text message if no images found
if len(content) == 1 and content[0]["type"] == "text":
    content = prompt

data = json.dumps({'model': MODEL, 'messages': [{'role': 'user', 'content': content}]}).encode()
req = urllib.request.Request(API_URL, data=data, headers={
    'Content-Type': 'application/json',
    'Authorization': f'Bearer {API_KEY}'
})
resp = urllib.request.urlopen(req)
body = json.loads(resp.read())
if 'choices' in body:
    print(body['choices'][0]['message']['content'])
else:
    print(f"API Error: {json.dumps(body, ensure_ascii=False)}")
