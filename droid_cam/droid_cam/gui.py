"""PySide6 window: start/stop the phone-camera stream and launch OBS."""

from __future__ import annotations

import shutil
import sys

from PySide6.QtCore import QProcess, QSettings, QTimer
from PySide6.QtGui import QCloseEvent
from PySide6.QtWidgets import (
    QApplication,
    QComboBox,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QPlainTextEdit,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from droid_cam.core import (
    FACINGS,
    FPS_CHOICES,
    ORIENTATIONS,
    PHONE_READY,
    SIZES,
    StreamSettings,
    device_present,
    modprobe_args,
    parse_adb_devices,
    phone_state,
)

APP_ID = "droid-cam"
POLL_MS = 2000
OBS_DELAY_MS = 2500
STOP_GRACE_MS = 3000

_COLORS = {"ok": "#2ecc71", "warn": "#f39c12", "bad": "#e74c3c"}
_PHONE_TEXT = {
    "device": ("ok", "Phone connected"),
    "unauthorized": ("warn", "Phone unauthorized: accept the USB debugging prompt"),
    "offline": ("bad", "Phone offline: replug the cable"),
    "none": ("bad", "No phone: plug in USB and enable USB debugging"),
    "no-adb": ("bad", "adb not found (install android-tools)"),
}


def _dot(level: str, text: str) -> str:
    """Return rich text with a coloured status dot."""
    return f'<span style="color:{_COLORS[level]}">●</span> {text}'


def _combo(items: list[tuple[str, str]], current: str) -> QComboBox:
    """Build a combo box of ``(label, data)`` items with ``current`` selected."""
    box = QComboBox()
    for label, data in items:
        box.addItem(label, data)
    index = box.findData(current)
    box.setCurrentIndex(max(index, 0))
    return box


class MainWindow(QWidget):
    """Main window: status, camera options, stream and OBS controls."""

    def __init__(self, settings: StreamSettings, *, autostart: bool = False) -> None:
        """Build the UI from ``settings``; ``autostart`` streams once the phone is ready."""
        super().__init__()
        self.setWindowTitle("Droid Cam")
        self.resize(460, 520)
        self._autostart = autostart
        self._phone = "none"
        self._serial = ""

        self._stream = QProcess(self)
        self._stream.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        self._stream.readyRead.connect(self._on_stream_output)
        self._stream.finished.connect(self._on_stream_finished)
        self._stream.errorOccurred.connect(self._on_stream_error)

        self._adb = QProcess(self)
        self._adb.finished.connect(self._on_adb_done)
        self._adb.errorOccurred.connect(self._on_adb_error)

        self._build_ui(settings)

        self._timer = QTimer(self)
        self._timer.timeout.connect(self._poll_phone)
        self._timer.start(POLL_MS)
        self._poll_phone()
        self._refresh()

    # ----- UI -----------------------------------------------------------

    def _build_ui(self, settings: StreamSettings) -> None:
        """Create widgets and layouts."""
        self._phone_label = QLabel()
        self._device_label = QLabel()
        self._stream_label = QLabel()
        self._load_button = QPushButton("Create virtual webcam…")
        self._load_button.setToolTip(
            "Runs modprobe v4l2loopback through pkexec (asks for a password)"
        )
        self._load_button.clicked.connect(self._load_module)

        self._facing = _combo([(f.capitalize(), f) for f in FACINGS], settings.facing)
        self._size = _combo([(s, s) for s in SIZES], settings.size)
        self._fps = _combo([(f"{f} fps", str(f)) for f in FPS_CHOICES], str(settings.fps))
        self._orientation = _combo(
            [(label, value) for value, label in ORIENTATIONS.items()], settings.orientation
        )

        form = QFormLayout()
        form.addRow("Camera", self._facing)
        form.addRow("Resolution", self._size)
        form.addRow("Frame rate", self._fps)
        form.addRow("Orientation", self._orientation)

        self._toggle = QPushButton("Start stream")
        self._toggle.clicked.connect(self._toggle_stream)
        self._obs = QPushButton("Start stream + open OBS")
        self._obs.clicked.connect(self._stream_and_obs)
        buttons = QHBoxLayout()
        buttons.addWidget(self._toggle)
        buttons.addWidget(self._obs)

        self._log = QPlainTextEdit()
        self._log.setReadOnly(True)
        self._log.setMaximumBlockCount(500)
        self._log.setPlaceholderText("scrcpy output appears here")

        layout = QVBoxLayout(self)
        for widget in (self._phone_label, self._device_label, self._load_button):
            layout.addWidget(widget)
        layout.addLayout(form)
        layout.addWidget(self._stream_label)
        layout.addLayout(buttons)
        layout.addWidget(self._log, 1)

    def settings(self) -> StreamSettings:
        """Return the stream settings currently selected in the UI."""
        return StreamSettings(
            facing=self._facing.currentData(),
            size=self._size.currentData(),
            fps=int(self._fps.currentData()),
            orientation=self._orientation.currentData(),
        )

    def _running(self) -> bool:
        """Return whether the scrcpy stream process is alive."""
        return self._stream.state() != QProcess.ProcessState.NotRunning

    def _ready(self) -> bool:
        """Return whether a stream can start right now."""
        return (
            self._phone == PHONE_READY
            and device_present(self.settings().device)
            and shutil.which("scrcpy") is not None
            and not self._running()
        )

    def _refresh(self) -> None:
        """Sync every label and button with the current state."""
        level, text = _PHONE_TEXT.get(self._phone, _PHONE_TEXT["none"])
        suffix = f" ({self._serial})" if self._serial else ""
        self._phone_label.setText(_dot(level, text + suffix))

        present = device_present(self.settings().device)
        self._device_label.setText(
            _dot("ok", f"Virtual webcam {self.settings().device}")
            if present
            else _dot("bad", "Virtual webcam missing (v4l2loopback not loaded)")
        )
        self._load_button.setVisible(not present)

        running = self._running()
        self._stream_label.setText(
            _dot("ok", "Streaming to OBS") if running else _dot("warn", "Stream stopped")
        )
        self._toggle.setText("Stop stream" if running else "Start stream")
        self._toggle.setEnabled(running or self._ready())
        self._obs.setEnabled(shutil.which("obs") is not None and (running or self._ready()))
        for box in (self._facing, self._size, self._fps, self._orientation):
            box.setEnabled(not running)

        if self._autostart and self._ready():
            self._autostart = False
            self.start_stream()

    # ----- phone polling -------------------------------------------------

    def _poll_phone(self) -> None:
        """Ask adb for the device list unless a query is already running."""
        if self._adb.state() == QProcess.ProcessState.NotRunning:
            self._adb.start("adb", ["devices"])

    def _on_adb_done(self) -> None:
        """Handle a finished ``adb devices`` query."""
        output = bytes(self._adb.readAllStandardOutput().data()).decode(errors="replace")
        self._phone, self._serial = phone_state(parse_adb_devices(output))
        self._refresh()

    def _on_adb_error(self, error: QProcess.ProcessError) -> None:
        """Flag a missing adb binary."""
        if error == QProcess.ProcessError.FailedToStart:
            self._phone, self._serial = "no-adb", ""
            self._refresh()

    # ----- stream control ------------------------------------------------

    def _toggle_stream(self) -> None:
        """Start or stop the stream depending on its state."""
        if self._running():
            self.stop_stream()
        else:
            self.start_stream()

    def start_stream(self) -> None:
        """Launch scrcpy with the selected settings."""
        if self._running():
            return
        args = self.settings().scrcpy_args()
        self._log.appendPlainText("$ scrcpy " + " ".join(args))
        self._stream.start("scrcpy", args)
        self._refresh()

    def stop_stream(self) -> None:
        """Ask scrcpy to exit, killing it if it ignores the request."""
        if not self._running():
            return
        self._stream.terminate()
        QTimer.singleShot(STOP_GRACE_MS, self._kill_if_running)

    def _kill_if_running(self) -> None:
        """Kill scrcpy if it survived the grace period."""
        if self._running():
            self._stream.kill()

    def _on_stream_output(self) -> None:
        """Append scrcpy output to the log."""
        text = bytes(self._stream.readAll().data()).decode(errors="replace").rstrip()
        if text:
            self._log.appendPlainText(text)

    def _on_stream_finished(self, code: int, _status: QProcess.ExitStatus) -> None:
        """Report the end of the stream."""
        self._log.appendPlainText(f"[scrcpy exited with code {code}]")
        self._refresh()

    def _on_stream_error(self, error: QProcess.ProcessError) -> None:
        """Report a scrcpy that could not start."""
        if error == QProcess.ProcessError.FailedToStart:
            self._log.appendPlainText("[scrcpy not found: install scrcpy]")
            self._refresh()

    def _stream_and_obs(self) -> None:
        """Start the stream if needed, then open OBS once frames can flow."""
        delay = 0
        if not self._running():
            self.start_stream()
            delay = OBS_DELAY_MS
        QTimer.singleShot(delay, self._open_obs)

    def _open_obs(self) -> None:
        """Start OBS detached so it outlives this window."""
        started, _pid = QProcess.startDetached("obs", [])
        if not started:
            self._log.appendPlainText("[could not start obs]")

    def _load_module(self) -> None:
        """Create the virtual webcam with a polkit-authorized modprobe."""
        argv = modprobe_args()
        self._log.appendPlainText("$ pkexec " + " ".join(argv))
        loader = QProcess(self)
        loader.finished.connect(lambda *_: self._refresh())
        loader.start("pkexec", argv)

    # ----- lifecycle -----------------------------------------------------

    def closeEvent(self, event: QCloseEvent) -> None:  # noqa: N802
        """Stop the stream, remember the settings, then close."""
        if self._running():
            self._stream.terminate()
            if not self._stream.waitForFinished(STOP_GRACE_MS):
                self._stream.kill()
                self._stream.waitForFinished(STOP_GRACE_MS)
        store = QSettings(APP_ID, APP_ID)
        current = self.settings()
        store.setValue("facing", current.facing)
        store.setValue("size", current.size)
        store.setValue("fps", current.fps)
        store.setValue("orientation", current.orientation)
        super().closeEvent(event)


def load_saved() -> StreamSettings:
    """Load the last-used settings, falling back to the defaults."""
    store = QSettings(APP_ID, APP_ID)
    default = StreamSettings()
    try:
        fps = int(str(store.value("fps", default.fps)))
    except TypeError, ValueError:
        fps = default.fps
    return StreamSettings(
        facing=str(store.value("facing", default.facing)),
        size=str(store.value("size", default.size)),
        fps=fps,
        orientation=str(store.value("orientation", default.orientation)),
    )


def run(overrides: StreamSettings | None = None, *, autostart: bool = False) -> int:
    """Run the Qt application and return its exit code."""
    app = QApplication(sys.argv[:1])
    app.setApplicationName("Droid Cam")
    app.setDesktopFileName(APP_ID)
    window = MainWindow(overrides or load_saved(), autostart=autostart)
    window.show()
    return app.exec()
