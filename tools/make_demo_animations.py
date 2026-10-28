#!/usr/bin/env python3
"""Generate looping exercise videos from the existing PNG guide art.

The source illustrations already contain useful start/end poses. This script
turns those poses into small pose-to-pose loops instead of redrawing the person.
"""

from __future__ import annotations

import math
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
EXERCISE_DIR = ROOT / "OfficeWorkoutCoach" / "Resources" / "Exercises"
SIZE = 1024
FPS = 24
DURATION = 4
FRAMES = FPS * DURATION

BG = (250, 247, 241)
BLUE = (0, 117, 201)
RED = (226, 51, 51)
INK = (36, 42, 50)
SOFT = (217, 211, 201)


@dataclass(frozen=True)
class Pose:
    box: tuple[int, int, int, int]
    max_width: int
    max_height: int
    contrast: float = 1.06
    brightness: float = 1.0
    y_offset: int = 0


@dataclass(frozen=True)
class SequenceSpec:
    name: str
    start: Pose
    end: Pose
    start_hint: tuple[tuple[int, int], tuple[int, int]] | None = None
    end_hint: tuple[tuple[int, int], tuple[int, int]] | None = None


SPECS = [
    SequenceSpec(
        name="gobletSquat",
        start=Pose((92, 40, 492, 1110), max_width=440, max_height=850, contrast=1.55, brightness=0.94),
        end=Pose((320, 140, 945, 1110), max_width=850, max_height=780, contrast=1.08, y_offset=20),
        start_hint=((510, 250), (510, 360)),
        end_hint=((510, 245), (510, 610)),
    ),
    SequenceSpec(
        name="romanianDeadlift",
        start=Pose((95, 80, 440, 1135), max_width=430, max_height=840, contrast=1.15),
        end=Pose((500, 255, 1120, 1125), max_width=850, max_height=760, contrast=1.08, y_offset=25),
        start_hint=((510, 240), (510, 775)),
        end_hint=((390, 425), (720, 355)),
    ),
    SequenceSpec(
        name="catCow",
        start=Pose((145, 80, 1050, 610), max_width=900, max_height=640, contrast=1.08),
        end=Pose((145, 610, 1050, 1155), max_width=900, max_height=640, contrast=1.08),
        start_hint=((330, 300), (710, 195)),
        end_hint=((330, 455), (710, 330)),
    ),
]


def ffmpeg_path() -> str:
    path = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
    if not Path(path).exists():
        raise RuntimeError("ffmpeg is required to generate the exercise videos")
    return path


def smoothstep(x: float) -> float:
    x = min(max(x, 0), 1)
    return x * x * (3 - 2 * x)


def pose_mix(progress: float) -> float:
    """Return 0 for start pose, 1 for end pose, with holds at each end."""
    if progress < 0.18:
        return 0
    if progress < 0.45:
        return smoothstep((progress - 0.18) / 0.27)
    if progress < 0.68:
        return 1
    if progress < 0.95:
        return 1 - smoothstep((progress - 0.68) / 0.27)
    return 0


def pulse(progress: float) -> float:
    return 0.5 + 0.5 * math.sin(2 * math.pi * progress)


def load_art(name: str) -> Image.Image:
    return Image.open(EXERCISE_DIR / f"{name}.png").convert("RGB")


def prepared_pose(art: Image.Image, pose: Pose) -> Image.Image:
    crop = art.crop(pose.box).convert("RGB")
    crop = ImageEnhance.Contrast(crop).enhance(pose.contrast)
    crop = ImageEnhance.Brightness(crop).enhance(pose.brightness)

    width, height = crop.size
    scale = min(pose.max_width / width, pose.max_height / height)
    size = (round(width * scale), round(height * scale))
    crop = crop.resize(size, Image.Resampling.LANCZOS).convert("RGBA")

    mask = Image.new("L", size, 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle((10, 10, size[0] - 10, size[1] - 10), radius=28, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(7))
    crop.putalpha(mask)
    return crop


def alpha_scaled(image: Image.Image, opacity: float) -> Image.Image:
    result = image.copy()
    alpha = result.getchannel("A").point(lambda value: int(value * opacity))
    result.putalpha(alpha)
    return result


def paste_center(frame: Image.Image, image: Image.Image, opacity: float, y_offset: int = 0) -> None:
    if opacity <= 0.01:
        return
    image = alpha_scaled(image, opacity)
    x = (SIZE - image.width) // 2
    y = (SIZE - image.height) // 2 + y_offset
    frame.alpha_composite(image, (x, y))


def draw_arrow(
    draw: ImageDraw.ImageDraw,
    start: tuple[int, int],
    end: tuple[int, int],
    progress: float,
    color: tuple[int, int, int] = BLUE,
) -> None:
    alpha = int(85 + 100 * pulse(progress))
    draw.line((*start, *end), fill=(*color, alpha), width=8)
    angle = math.atan2(end[1] - start[1], end[0] - start[0])
    size = 26
    left = (end[0] - size * math.cos(angle - 0.55), end[1] - size * math.sin(angle - 0.55))
    right = (end[0] - size * math.cos(angle + 0.55), end[1] - size * math.sin(angle + 0.55))
    draw.polygon([end, left, right], fill=(*color, alpha))


def draw_stage_indicator(draw: ImageDraw.ImageDraw, mix: float) -> None:
    y = 928
    x1, x2 = 380, 644
    draw.line((x1, y, x2, y), fill=(*SOFT, 220), width=7)
    active_x = round(x1 + (x2 - x1) * mix)
    draw.line((x1, y, active_x, y), fill=(*BLUE, 210), width=7)

    font = ImageFont.load_default()
    for idx, (x, active) in enumerate([(x1, 1 - mix), (x2, mix)], start=1):
        radius = 27
        color = BLUE if active > 0.5 else (173, 181, 190)
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=(*color, 235))
        draw.text((x - 3, y - 5), str(idx), fill=(255, 255, 255, 255), font=font)

    dot_radius = 13
    draw.ellipse(
        (active_x - dot_radius, y - dot_radius, active_x + dot_radius, y + dot_radius),
        fill=(*INK, 235),
    )


def draw_frame(spec: SequenceSpec, art: Image.Image, start_pose: Image.Image, end_pose: Image.Image, idx: int) -> Image.Image:
    progress = idx / FRAMES
    mix = pose_mix(progress)
    frame = Image.new("RGBA", (SIZE, SIZE), (*BG, 255))

    # A faint destination pose gives the viewer context, while the active pose
    # dissolves between real source-art poses.
    paste_center(frame, start_pose, 0.12 + 0.88 * (1 - mix), spec.start.y_offset)
    paste_center(frame, end_pose, 0.12 + 0.88 * mix, spec.end.y_offset)

    overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    if mix < 0.5 and spec.start_hint:
        draw_arrow(draw, spec.start_hint[0], spec.start_hint[1], progress)
    elif spec.end_hint:
        color = RED if spec.name == "romanianDeadlift" else BLUE
        draw_arrow(draw, spec.end_hint[0], spec.end_hint[1], progress, color=color)

    draw_stage_indicator(draw, mix)
    frame.alpha_composite(overlay)
    return frame.convert("RGB")


def write_video(spec: SequenceSpec) -> None:
    art = load_art(spec.name)
    start_pose = prepared_pose(art, spec.start)
    end_pose = prepared_pose(art, spec.end)
    tmp = Path(tempfile.mkdtemp(prefix=f"luma-{spec.name}-"))
    try:
        for idx in range(FRAMES):
            draw_frame(spec, art, start_pose, end_pose, idx).save(tmp / f"frame_{idx:04d}.png")

        output = EXERCISE_DIR / f"{spec.name}.mp4"
        subprocess.run(
            [
                ffmpeg_path(),
                "-y",
                "-framerate",
                str(FPS),
                "-i",
                str(tmp / "frame_%04d.png"),
                "-vf",
                "format=yuv420p",
                "-c:v",
                "libx264",
                "-crf",
                "20",
                "-movflags",
                "+faststart",
                str(output),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        print(output)
    finally:
        shutil.rmtree(tmp)


def main() -> None:
    EXERCISE_DIR.mkdir(parents=True, exist_ok=True)
    for spec in SPECS:
        write_video(spec)


if __name__ == "__main__":
    main()
