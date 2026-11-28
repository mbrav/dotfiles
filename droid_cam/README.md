# droid_cam

Small GUI that turns an Android phone camera into a virtual webcam for OBS,
using `scrcpy` (camera source) and `v4l2loopback`. Tested with a Pixel 8 on
GrapheneOS over USB.

## Requirements

- `scrcpy`, `android-tools` (adb), `obs`
- `v4l2loopback` with a node at `/dev/video10` (the GUI can create it through
  `pkexec`, or see "Persistent webcam" below)
- Phone: USB debugging on, computer authorized

## Run

    uvx --from ~/dev/github.com/mbrav/dotfiles/droid_cam droid-cam

Or from this directory: `uv run droid-cam`. Install it permanently with
`uv tool install ~/dev/github.com/mbrav/dotfiles/droid_cam`.

`uvx` caches the build, so after editing the code run it with `--refresh`
(or use `uv run`).

Options: `--camera back|front`, `--size`, `--fps 30|60`,
`--orientation 90|270|0|180`, `--start` (stream once the phone is ready) and
`--print-cmd` (print the scrcpy command and exit). Last-used choices are saved.

`--orientation 90` gives an upright 1080x1920 portrait frame, matching an OBS
canvas of 1080x1920.

## KDE launcher

`droid-cam.desktop` runs the app through `uvx`. Link it into the application
menu once:

    ln -sf ~/dev/github.com/mbrav/dotfiles/droid_cam/droid-cam.desktop \
        ~/.local/share/applications/droid-cam.desktop

Then find "Droid Cam" in the launcher or KRunner, and pin it to the panel.

## Persistent webcam

To keep `/dev/video10` across reboots:

    echo v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf
    echo 'options v4l2loopback video_nr=10 card_label="Pixel 8" exclusive_caps=1' \
        | sudo tee /etc/modprobe.d/v4l2loopback.conf

## Develop

    uv run ruff format . && uv run ruff check .
    uv run ty check
    uv run pytest
