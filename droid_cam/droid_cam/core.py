"""Qt-free helpers: stream settings, scrcpy command line and adb/v4l2 state."""

from __future__ import annotations

from dataclasses import dataclass, replace
from pathlib import Path

V4L2_DEVICE = "/dev/video10"
V4L2_NR = 10
V4L2_LABEL = "Pixel 8"

FACINGS = ("back", "front")
SIZES = ("1920x1080", "1280x720", "3840x2160")
FPS_CHOICES = (30, 60)
# scrcpy --capture-orientation value -> human label. 90 yields an upright
# 1080x1920 frame when the phone is mounted in portrait.
ORIENTATIONS = {
    "90": "Portrait",
    "270": "Portrait (flipped)",
    "0": "Landscape",
    "180": "Landscape (flipped)",
}

PHONE_READY = "device"


@dataclass(frozen=True)
class StreamSettings:
    """Everything that shapes the scrcpy camera stream."""

    facing: str = "back"
    size: str = "1920x1080"
    fps: int = 30
    orientation: str = "90"
    device: str = V4L2_DEVICE

    def with_overrides(self, **changes: object) -> StreamSettings:
        """Return a copy with every non-``None`` change applied."""
        return replace(self, **{k: v for k, v in changes.items() if v is not None})

    def scrcpy_args(self) -> list[str]:
        """Return the scrcpy arguments (without the program name)."""
        return [
            "--video-source=camera",
            f"--camera-facing={self.facing}",
            f"--camera-size={self.size}",
            f"--camera-fps={self.fps}",
            f"--capture-orientation={self.orientation}",
            f"--v4l2-sink={self.device}",
            "--no-playback",
            "--no-audio",
        ]


def parse_adb_devices(output: str) -> list[tuple[str, str]]:
    """Parse ``adb devices`` output into ``(serial, state)`` pairs."""
    devices: list[tuple[str, str]] = []
    for line in output.splitlines():
        line = line.strip()
        if not line or line.startswith(("List of devices", "*")):
            continue
        parts = line.split()
        if len(parts) >= 2:
            devices.append((parts[0], parts[1]))
    return devices


def phone_state(devices: list[tuple[str, str]]) -> tuple[str, str]:
    """Pick the most useful ``(state, serial)``: ready beats unauthorized beats offline."""
    for wanted in (PHONE_READY, "unauthorized", "offline"):
        for serial, state in devices:
            if state == wanted:
                return state, serial
    return "none", ""


def device_present(device: str = V4L2_DEVICE) -> bool:
    """Return whether the virtual webcam node exists."""
    return Path(device).exists()


def modprobe_args() -> list[str]:
    """Return the ``modprobe`` arguments that create the virtual webcam."""
    return [
        "modprobe",
        "v4l2loopback",
        f"video_nr={V4L2_NR}",
        f"card_label={V4L2_LABEL}",
        "exclusive_caps=1",
    ]
