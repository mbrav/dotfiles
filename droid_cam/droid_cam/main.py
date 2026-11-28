"""Command-line entry point for the ``droid-cam`` console script.

Opens the GUI by default. ``--print-cmd`` prints the scrcpy command that the
GUI would run, without importing Qt.
"""

from __future__ import annotations

import argparse
import shlex
import sys

from droid_cam.core import FACINGS, FPS_CHOICES, ORIENTATIONS, SIZES, StreamSettings


def _parser() -> argparse.ArgumentParser:
    """Build the argument parser."""
    parser = argparse.ArgumentParser(
        prog="droid-cam",
        description="Use an Android phone camera as a virtual webcam for OBS.",
    )
    parser.add_argument("--camera", choices=FACINGS, help="camera to use (default: saved or back)")
    parser.add_argument("--size", choices=SIZES, help="capture size (default: saved or 1920x1080)")
    parser.add_argument(
        "--fps", type=int, choices=FPS_CHOICES, help="frame rate (default: saved or 30)"
    )
    parser.add_argument(
        "--orientation",
        choices=list(ORIENTATIONS),
        help="scrcpy capture orientation; 90 = upright portrait (default: saved or 90)",
    )
    parser.add_argument(
        "--start", action="store_true", help="start streaming as soon as the phone is ready"
    )
    parser.add_argument(
        "--print-cmd", action="store_true", help="print the scrcpy command and exit"
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """Run the GUI, or print the scrcpy command with ``--print-cmd``."""
    args = _parser().parse_args(argv)
    overrides = {
        "facing": args.camera,
        "size": args.size,
        "fps": args.fps,
        "orientation": args.orientation,
    }

    if args.print_cmd:
        settings = StreamSettings().with_overrides(**overrides)
        print(shlex.join(["scrcpy", *settings.scrcpy_args()]))
        return 0

    from droid_cam.gui import load_saved, run

    return run(load_saved().with_overrides(**overrides), autostart=args.start)


if __name__ == "__main__":
    sys.exit(main())
