from droid_cam.core import StreamSettings, parse_adb_devices, phone_state

ADB_OUT = """* daemon not running; starting now at tcp:5037
* daemon started successfully
List of devices attached
38291FDJH000HN\tunauthorized
ABC123\tdevice

"""


def test_parse_adb_devices_skips_noise():
    assert parse_adb_devices(ADB_OUT) == [("38291FDJH000HN", "unauthorized"), ("ABC123", "device")]


def test_phone_state_prefers_ready():
    assert phone_state(parse_adb_devices(ADB_OUT)) == ("device", "ABC123")


def test_phone_state_none_when_empty():
    assert phone_state(parse_adb_devices("List of devices attached\n\n")) == ("none", "")


def test_phone_state_unauthorized():
    assert phone_state([("S", "unauthorized")]) == ("unauthorized", "S")


def test_scrcpy_args_defaults_are_portrait_1080p30():
    args = StreamSettings().scrcpy_args()
    assert "--camera-facing=back" in args
    assert "--camera-size=1920x1080" in args
    assert "--camera-fps=30" in args
    assert "--capture-orientation=90" in args
    assert "--v4l2-sink=/dev/video10" in args


def test_with_overrides_ignores_none():
    base = StreamSettings()
    changed = base.with_overrides(facing="front", fps=None)
    assert changed.facing == "front"
    assert changed.fps == base.fps
