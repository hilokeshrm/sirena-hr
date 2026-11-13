"""Builds the app icons for iPhone and Android from assets/sirena-eyes.png.

The wordmark is unreadable at icon sizes, so the icon is the eyes alone on the app's dark
background. iPhone icons must not be transparent, so everything is flattened.

    cd app && python tool/make-icons.py
"""

import json
import pathlib

from PIL import Image

APP = pathlib.Path(__file__).resolve().parent.parent
BACKGROUND = (42, 42, 42)  # C.ink, the dark used across the app
PADDING = 0.12

source = Image.open(APP / "assets/sirena-eyes.png").convert("RGBA")
source = source.crop(source.split()[3].getbbox())


def icon(px: int) -> Image.Image:
    box = int(px * (1 - 2 * PADDING))
    scale = min(box / source.width, box / source.height)
    art = source.resize((max(1, round(source.width * scale)), max(1, round(source.height * scale))), Image.LANCZOS)
    out = Image.new("RGB", (px, px), BACKGROUND)
    out.paste(art, ((px - art.width) // 2, (px - art.height) // 2), art)
    return out


icon_set = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
contents = json.loads((icon_set / "Contents.json").read_text())
sizes = {
    image["filename"]: round(float(image["size"].split("x")[0]) * int(image["scale"].rstrip("x")))
    for image in contents["images"]
    if image.get("filename")
}
for filename, px in sizes.items():
    icon(px).save(icon_set / filename)
print(f"iPhone: {len(sizes)} icons")

for folder, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
    icon(px).save(APP / f"android/app/src/main/res/mipmap-{folder}/ic_launcher.png")
print("Android: 5 icons")
