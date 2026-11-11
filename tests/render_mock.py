"""Layout preview from the Lua smoke-test widget tree, not a WoW screenshot."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).parent
FONT = '/usr/share/fonts/TTF/DejaVuSans.ttf'
if not Path(FONT).exists():
    FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'

def color(v, default=(210, 215, 225, 255)):
    if not v:
        return default
    return tuple(int(max(0, min(1, x)) * 255) for x in (v[:3] + [v[3] if len(v) > 3 else 1]))

for tab in ('pvp', 'quests', 'gold', 'gear', 'settings', 'pvp-party', 'quests-party', 'gold-party', 'gear-party'):
    items = json.loads((ROOT / (tab + '.json')).read_text())
    canvas = Image.new('RGBA', (850, 426), (14, 17, 21, 255))
    overflow = []
    for o in items:
        x, y, w, h = [round(o[k]) for k in ('x', 'y', 'w', 'h')]
        if w <= 0 or h <= 0:
            continue
        layer = Image.new('RGBA', canvas.size)
        d = ImageDraw.Draw(layer)
        if o.get('bg'):
            d.rectangle((x, y, x+w-1, y+h-1), fill=color(o['bg']), outline=color(o.get('border')))
        if o['kind'] == 'StatusBar':
            d.rectangle((x, y, x+int(w*o.get('value', 0)), y+h), fill=color(o.get('color')))
        if o['kind'] == 'Texture':
            d.rectangle((x, y, x+w, y+h), fill=(44, 49, 57), outline=(80, 88, 100))
            if 'CLASSES' in o.get('texture', ''):
                d.ellipse((x+4, y+4, x+w-4, y+h-4), fill=(150, 121, 80))
        if o['kind'] == 'FontString':
            text = o.get('text', '')
            font = ImageFont.truetype(FONT, o.get('font', 13))
            if d.textlength(text, font=font) > w:
                overflow.append(text)
                while text and d.textlength(text+'…', font=font) > w:
                    text = text[:-1]
                text += '…'
            tw = d.textlength(text, font=font)
            tx = x + ((w-tw)/2 if o.get('align') == 'CENTER' else w-tw if o.get('align') == 'RIGHT' else 0)
            d.text((tx, y+h/2), text, font=font, fill=color(o.get('color')), anchor='lm')
        if o.get('clip'):
            cx, cy, cw, ch = map(round, o['clip'])
            crop = layer.crop((cx, cy, cx+cw, cy+ch))
            layer = Image.new('RGBA', canvas.size)
            layer.paste(crop, (cx, cy))
        canvas.alpha_composite(layer)
    canvas.convert('RGB').save(ROOT / (tab + '-mock.png'))
    print(tab, 'clipped text:', sorted(set(overflow)))
