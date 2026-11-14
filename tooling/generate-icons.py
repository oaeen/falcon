#!/usr/bin/env python3
"""Generate Falcon branding PNGs, Android/iOS/macOS app icons, and visual previews."""

from __future__ import annotations

import re
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

REPO_ROOT = Path(__file__).resolve().parent.parent
BRANDING_DIR = REPO_ROOT / "assets" / "branding"
SHOTS_DIR = REPO_ROOT / "shots"
ANDROID_RES = REPO_ROOT / "android" / "app" / "src" / "main" / "res"
IOS_ICONSET = REPO_ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
MACOS_ICONSET = REPO_ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"

CHROME_BIN = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

ANDROID_MIPMAP_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

ANDROID_ADAPTIVE_SIZES = {
    "drawable-mdpi": 108,
    "drawable-hdpi": 162,
    "drawable-xhdpi": 216,
    "drawable-xxhdpi": 324,
    "drawable-xxxhdpi": 432,
}

IOS_SIZES = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

MACOS_SIZES = {
    "app_icon_16.png": 16,
    "app_icon_32.png": 32,
    "app_icon_64.png": 64,
    "app_icon_128.png": 128,
    "app_icon_256.png": 256,
    "app_icon_512.png": 512,
    "app_icon_1024.png": 1024,
}


def render_svg_chrome(svg_text: str, size: int, tmp_dir: Path, name: str) -> Image.Image:
    """Rasterize an SVG at exact pixel dimensions with transparent alpha via headless Chrome."""
    html_path = tmp_dir / f"{name}.html"
    png_path = tmp_dir / f"{name}.png"
    html = f"""<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
  html, body {{
    margin: 0;
    padding: 0;
    width: {size}px;
    height: {size}px;
    overflow: hidden;
    background: transparent;
  }}
  svg {{
    display: block;
    width: {size}px;
    height: {size}px;
  }}
</style>
</head>
<body>{svg_text}</body>
</html>
"""
    html_path.write_text(html, encoding="utf-8")
    cmd = [
        CHROME_BIN,
        "--headless=new",
        "--disable-gpu",
        "--no-sandbox",
        "--hide-scrollbars",
        "--default-background-color=00000000",
        f"--window-size={size},{size}",
        "--force-device-scale-factor=1",
        f"--screenshot={png_path}",
        html_path.as_uri(),
    ]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return Image.open(png_path).convert("RGBA")


def make_square_svg(rounded_svg: str) -> str:
    """Convert rounded icon rect (rx=224) into full-bleed square for iOS / badge crops."""
    return re.sub(r'\s+rx="224"\s+ry="224"', "", rounded_svg)


def make_circle_masked(img: Image.Image) -> Image.Image:
    size = img.width
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, size - 1, size - 1), fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def make_squircle_mask(size: int, power: float = 4.2) -> Image.Image:
    """Generate a smooth superellipse mask (macOS / modern Android squircle)."""
    mask = Image.new("L", (size, size), 0)
    pixels = mask.load()
    half = (size - 1) / 2.0
    for y in range(size):
        ny = abs(y - half) / half
        yp = ny ** power
        for x in range(size):
            nx = abs(x - half) / half
            d = (nx ** power + yp) ** (1.0 / power)
            if d <= 0.992:
                pixels[x, y] = 255
            elif d < 1.008:
                alpha = max(0, min(255, int(255 * (1.008 - d) / 0.016)))
                pixels[x, y] = alpha
    return mask


def make_macos_icon(square_img: Image.Image) -> Image.Image:
    """Create 1024x1024 macOS icon: white padded squircle with 1.5px #E2E8F0 edge + soft shadow."""
    canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    inner_size = 824
    offset = (1024 - inner_size) // 2
    resized = square_img.resize((inner_size, inner_size), Image.Resampling.LANCZOS)
    mask = make_squircle_mask(inner_size, power=4.5)

    # Crisp subtle 1.5px #E2E8F0 border ring along the inner squircle edge.
    border_overlay = Image.new("RGBA", (inner_size, inner_size), (0, 0, 0, 0))
    b_pix = border_overlay.load()
    half = (inner_size - 1) / 2.0
    power = 4.5
    inner_edge = 1.0 - (1.5 / half)
    for y in range(inner_size):
        ny = abs(y - half) / half
        yp = ny ** power
        for x in range(inner_size):
            nx = abs(x - half) / half
            d = (nx ** power + yp) ** (1.0 / power)
            if inner_edge <= d <= 1.006:
                b_pix[x, y] = (226, 232, 240, 255)  # #E2E8F0

    shadow = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    shadow_shape = Image.new("RGBA", (inner_size, inner_size), (15, 23, 42, 42))
    shadow.paste(shadow_shape, (offset, offset + 12), mask)
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=16))

    canvas = Image.alpha_composite(canvas, shadow)
    tile = Image.new("RGBA", (inner_size, inner_size), (0, 0, 0, 0))
    tile.paste(resized, (0, 0), mask)
    tile = Image.alpha_composite(tile, border_overlay)
    masked_tile = Image.new("RGBA", (inner_size, inner_size), (0, 0, 0, 0))
    masked_tile.paste(tile, (0, 0), mask)
    canvas.paste(masked_tile, (offset, offset), masked_tile)
    return canvas


def write_android_adaptive_xmls() -> None:
    anydpi_dir = ANDROID_RES / "mipmap-anydpi-v26"
    anydpi_dir.mkdir(parents=True, exist_ok=True)
    adaptive_xml = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
"""
    (anydpi_dir / "ic_launcher.xml").write_text(adaptive_xml, encoding="utf-8")
    (anydpi_dir / "ic_launcher_round.xml").write_text(adaptive_xml, encoding="utf-8")

    drawable_dir = ANDROID_RES / "drawable"
    drawable_dir.mkdir(parents=True, exist_ok=True)
    bg_xml = """<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:fillColor="#FFFFFFFF" android:pathData="M0,0h108v108h-108z" />
</vector>
"""
    (drawable_dir / "ic_launcher_background.xml").write_text(bg_xml, encoding="utf-8")

    # Cute minimalist falcon head silhouette for monochrome Android status bar notifications.
    stat_xml = """<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:fillType="evenOdd"
        android:pathData="M11.1,3.2 C10.4,1.9 11.6,1.0 12.6,1.9 C13.3,1.1 14.5,1.7 13.8,3.1 C13.5,3.7 13.0,4.0 12.4,4.2 C16.3,4.4 18.8,7.2 18.7,11.0 C19.8,11.8 20.5,13.6 20.0,15.7 C19.5,17.7 17.9,19.1 16.0,19.5 C14.8,20.5 13.4,21.0 12.0,21.0 C10.6,21.0 9.2,20.5 8.0,19.5 C6.1,19.1 4.5,17.7 4.0,15.7 C3.5,13.6 4.2,11.8 5.3,11.0 C5.2,7.2 7.6,4.5 11.1,4.2 Z M9.2,9.7 A1.45,1.45 0 1,0 9.2,12.6 A1.45,1.45 0 1,0 9.2,9.7 Z M14.8,9.7 A1.45,1.45 0 1,0 14.8,12.6 A1.45,1.45 0 1,0 14.8,9.7 Z M12.0,11.4 C13.1,11.4 13.8,12.2 13.5,13.0 C13.2,13.8 12.4,14.5 12.0,14.5 C11.6,14.5 10.8,13.8 10.5,13.0 C10.2,12.2 10.9,11.4 12.0,11.4 Z" />
</vector>
"""
    (drawable_dir / "ic_stat_falcon.xml").write_text(stat_xml, encoding="utf-8")


def build_adaptive_preview_sheet(
    fg_1024: Image.Image,
    rounded_1024: Image.Image,
) -> Image.Image:
    """Create a 2x2 visual inspection sheet across masks and light (#E6E9EF) / dark (#121824) backdrops."""
    adaptive_full = Image.new("RGBA", (1024, 1024), (255, 255, 255, 255))
    adaptive_full.alpha_composite(fg_1024)

    tile_size = 380
    sheet = Image.new("RGBA", (960, 960), (230, 233, 239, 255))  # #E6E9EF
    draw = ImageDraw.Draw(sheet)

    draw.rectangle((480, 480, 960, 960), fill=(18, 24, 36, 255))  # #121824
    draw.line((480, 0, 480, 960), fill=(203, 213, 225, 255), width=2)
    draw.line((0, 480, 960, 480), fill=(203, 213, 225, 255), width=2)

    crop_margin = int(round(1024 * (18.0 / 108.0)))
    adaptive_cropped = adaptive_full.crop(
        (crop_margin, crop_margin, 1024 - crop_margin, 1024 - crop_margin)
    ).resize((tile_size, tile_size), Image.Resampling.LANCZOS)

    circle_tile = make_circle_masked(adaptive_cropped)
    squircle_tile = Image.new("RGBA", (tile_size, tile_size), (0, 0, 0, 0))
    squircle_tile.paste(adaptive_cropped, (0, 0), make_squircle_mask(tile_size, power=4.2))
    rounded_tile = rounded_1024.resize((tile_size, tile_size), Image.Resampling.LANCZOS)

    dark_squircle = Image.new("RGBA", (tile_size, tile_size), (0, 0, 0, 0))
    dark_squircle.paste(adaptive_cropped, (0, 0), make_squircle_mask(tile_size, power=4.2))

    positions = [
        (50, 50, circle_tile),
        (530, 50, squircle_tile),
        (50, 530, rounded_tile),
        (530, 530, dark_squircle),
    ]

    for x, y, tile in positions:
        sheet.paste(tile, (x, y), tile)

    return sheet.convert("RGB")


def make_transparent_mascot(fg_1024: Image.Image, out_size: int = 256, fill_ratio: float = 0.90) -> Image.Image:
    """Crop the transparent foreground SVG render tightly and center on a clean RGBA canvas."""
    bbox = fg_1024.getbbox()
    if bbox is None:
        return fg_1024.resize((out_size, out_size), Image.Resampling.LANCZOS)
    cropped = fg_1024.crop(bbox)
    cw, ch = cropped.size
    target_max = int(round(out_size * fill_ratio))
    scale = min(target_max / cw, target_max / ch)
    nw = max(1, int(round(cw * scale)))
    nh = max(1, int(round(ch * scale)))
    resized = cropped.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (out_size, out_size), (0, 0, 0, 0))
    ox = (out_size - nw) // 2
    oy = (out_size - nh) // 2
    canvas.paste(resized, (ox, oy), resized)
    return canvas


def main() -> None:
    rounded_svg_path = BRANDING_DIR / "falcon_icon.svg"
    fg_svg_path = BRANDING_DIR / "falcon_icon_foreground.svg"
    rounded_svg = rounded_svg_path.read_text(encoding="utf-8")
    fg_svg = fg_svg_path.read_text(encoding="utf-8")
    square_svg = make_square_svg(rounded_svg)

    SHOTS_DIR.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        rounded_2048 = render_svg_chrome(rounded_svg, 2048, tmp_dir, "rounded")
        square_2048 = render_svg_chrome(square_svg, 2048, tmp_dir, "square")
        fg_1024 = render_svg_chrome(fg_svg, 1024, tmp_dir, "foreground")

        rounded_1024 = rounded_2048.resize((1024, 1024), Image.Resampling.LANCZOS)
        square_1024 = square_2048.resize((1024, 1024), Image.Resampling.LANCZOS)

        # Flutter assets: 256x256 white-backdrop icon + tight transparent mascot.
        square_1024.resize((256, 256), Image.Resampling.LANCZOS).save(
            BRANDING_DIR / "falcon_icon_256.png", format="PNG", optimize=True
        )
        make_transparent_mascot(fg_1024, 256).save(
            BRANDING_DIR / "falcon_mascot.png", format="PNG", optimize=True
        )

        # Visual preview sheets.
        rounded_1024.save(SHOTS_DIR / "icon_preview_1024.png", format="PNG")
        adaptive_sheet = build_adaptive_preview_sheet(fg_1024, rounded_1024)
        adaptive_sheet.save(SHOTS_DIR / "icon_preview_adaptive_sheet.png", format="PNG")

        # Android mipmaps (legacy rounded & circle).
        circle_1024 = make_circle_masked(square_1024)
        for folder, px in ANDROID_MIPMAP_SIZES.items():
            out_dir = ANDROID_RES / folder
            out_dir.mkdir(parents=True, exist_ok=True)
            rounded_1024.resize((px, px), Image.Resampling.LANCZOS).save(
                out_dir / "ic_launcher.png", format="PNG", optimize=True
            )
            circle_1024.resize((px, px), Image.Resampling.LANCZOS).save(
                out_dir / "ic_launcher_round.png", format="PNG", optimize=True
            )

        # Android adaptive foreground densities + white background XML.
        for folder, px in ANDROID_ADAPTIVE_SIZES.items():
            out_dir = ANDROID_RES / folder
            out_dir.mkdir(parents=True, exist_ok=True)
            fg_1024.resize((px, px), Image.Resampling.LANCZOS).save(
                out_dir / "ic_launcher_foreground.png", format="PNG", optimize=True
            )
        write_android_adaptive_xmls()

        # iOS AppIcon (opaque RGB, zero alpha channel, pure white background).
        ios_rgb_1024 = square_1024.convert("RGB")
        for filename, px in IOS_SIZES.items():
            ios_rgb_1024.resize((px, px), Image.Resampling.LANCZOS).save(
                IOS_ICONSET / filename, format="PNG", optimize=True
            )

        # macOS AppIcon (padded white squircle with subtle edge & shadow on transparent canvas).
        macos_1024 = make_macos_icon(square_1024)
        for filename, px in MACOS_SIZES.items():
            macos_1024.resize((px, px), Image.Resampling.LANCZOS).save(
                MACOS_ICONSET / filename, format="PNG", optimize=True
            )

    print("Generated all white-background Falcon icons and previews successfully.")


if __name__ == "__main__":
    main()
