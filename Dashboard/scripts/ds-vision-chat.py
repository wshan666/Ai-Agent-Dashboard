#!/usr/bin/env python3
"""DeepSeek Vision Chat — supports image URLs embedded in prompt text."""
import sys, json, urllib.request, base64, re, os

API_KEY = os.environ.get('DEEPSEEK_API_KEY', '').strip()
API_URL = 'https://api.deepseek.com/v1/chat/completions'
MODEL = 'deepseek-v4-pro'

if not API_KEY:
    print('DEEPSEEK_API_KEY is not configured', file=sys.stderr)
    sys.exit(2)

prompt = sys.stdin.read()

# Find full image URLs (not just captures from groups)
image_urls = list(set(re.findall(
    r'https?://[\d.]+:?\d*/uploads/[\w.-]+\.(?:jpe?g|png|gif|webp|bmp)',
    prompt, re.IGNORECASE
)))

messages = [{"role": "user", "content": []}]
messages[0]["content"].append({"type": "text", "text": prompt})

for url in image_urls:
    try:
        req = urllib.request.Request(url)
        img_data = urllib.request.urlopen(req, timeout=10).read()
        if len(img_data) < 64:
            continue
        b64 = base64.b64encode(img_data).decode('ascii')
        ext = url.rsplit('.', 1)[-1].lower().split('?')[0]
        mime = f'image/{ext}' if ext in ('png', 'gif', 'webp', 'bmp') else 'image/jpeg'
        messages[0]["content"].append({
            "type": "image_url",
            "image_url": {"url": f"data:{mime};base64,{b64}"}
        })
    except Exception as e:
        messages[0]["content"].append({
            "type": "text",
            "text": f"\n[无法下载图片 {url}: {e}]"
        })

# Fallback: if no images found, use plain text
if len(messages[0]["content"]) == 1 and messages[0]["content"][0]["type"] == "text":
    messages[0]["content"] = prompt

data = json.dumps({'model': MODEL, 'messages': messages}).encode()
req = urllib.request.Request(API_URL, data=data, headers={
    'Content-Type': 'application/json',
    'Authorization': f'Bearer {API_KEY}'
})
resp = urllib.request.urlopen(req)
body = json.loads(resp.read())
print(body['choices'][0]['message']['content'])
