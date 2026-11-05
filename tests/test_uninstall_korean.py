"""Exercise the migration uninstaller against disposable installed settings."""

import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/uninstall-korean.sh"
PLUGIN = "minsoft1115.fcitx"
ENVIRONMENT = "INPUT_METHOD=fcitx\nQT_IM_MODULE=fcitx\nXMODIFIERS=@im=fcitx\nSDL_IM_MODULE=fcitx\n"


class UninstallKoreanTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="uninstall-korean-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.config = self.root / "config"
        self.bin = self.root / "bin"
        self.stock = self.root / "stock"
        self.env = {**os.environ, "OMARCHY_PATH": str(self.stock)}
        self.original_main = '-- user settings\n\n-- keep this blank line\n\n'
        self.put("config/hypr/hyprland.lua", self.original_main + '\n-- setup-korean:begin\nrequire("minsoft1115.hypr.korean-input")\nrequire("minsoft1115.hypr.korean-bindings")\n-- setup-korean:end\n')
        self.put("config/hypr/input.lua", "-- personal input settings\n")
        self.put("config/hypr/bindings.lua", "-- personal bindings\n")
        for name in ("korean-input.lua", "korean-bindings.lua", "sudo-pop.lua"):
            self.put("config/minsoft1115/hypr/" + name, "-- " + name + "\n")
        self.put("bin/omarchy-latin-launch", "#!/bin/bash\n# fcitx5 입력을 영문으로 강제 전환한 뒤 지정한 명령 실행\nexec \"$@\"\n")
        self.put("config/environment.d/fcitx.conf", ENVIRONMENT)
        self.put("stock/default/environment.d/10-omarchy-fcitx.conf", ENVIRONMENT)
        for base in ("config", "stock/config"):
            self.put(base + "/autostart/org.fcitx.Fcitx5.desktop", "[Desktop Entry]\nHidden=true\n")
        self.shell = {"bar": {"layout": {"right": ["omarchy.keyboard", {"id": PLUGIN}, "omarchy.clock"], "left": [PLUGIN, "other.widget"]}}, "plugins": [{"id": PLUGIN, "enabled": True}, "other.widget"], "disabledPlugins": [PLUGIN, "other.disabled"], "personal": {"keep": True}}
        self.put("config/omarchy/shell.json", json.dumps(self.shell))
        self.put("config/omarchy/plugins/" + PLUGIN + "/manifest.json", json.dumps({"id": PLUGIN}))
        self.put("config/omarchy/plugins/" + PLUGIN + "/ImStatus.qml", "// user-tuned widget\n")
        for name, text in {"fcitx5/config": "[Hotkey/TriggerKeys]\n0=Hangul\n", "fcitx5/profile": "DefaultIM=hangul\n", "omarchy/keyboard-layouts": "XKBLAYOUT=kr\nXKBVARIANT=kr104\n", "omarchy/language": "en\n", "fontconfig/conf.d/personal.conf": "keep fonts\n"}.items():
            self.put("config/" + name, text)

    def put(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def snapshot(self):
        return {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}

    def run_uninstall(self, *args, reload=False):
        command = ["bash", str(SCRIPT), "--config-dir", str(self.config), "--bin-dir", str(self.bin)]
        if not reload:
            command.append("--no-reload")
        return subprocess.run(command + list(args), env=self.env, text=True, capture_output=True, timeout=15)

    def test_dry_run_changes_nothing(self):
        before = self.snapshot()
        result = self.run_uninstall("--dry-run", reload=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, self.snapshot())
        self.assertIn("제거 예정", result.stdout)

    def test_removes_repo_settings_and_preserves_working_input(self):
        before = self.snapshot()
        result = self.run_uninstall()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.config / "hypr/hyprland.lua").read_text(), self.original_main)
        removed = ["minsoft1115/hypr/korean-input.lua", "minsoft1115/hypr/korean-bindings.lua", "environment.d/fcitx.conf", "omarchy/plugins/" + PLUGIN]
        for name in removed:
            self.assertFalse((self.config / name).exists(), name)
        self.assertFalse((self.bin / "omarchy-latin-launch").exists())
        for name in ["fcitx5/config", "fcitx5/profile", "omarchy/keyboard-layouts", "omarchy/language", "fontconfig/conf.d/personal.conf", "minsoft1115/hypr/sudo-pop.lua", "autostart/org.fcitx.Fcitx5.desktop"]:
            self.assertEqual((self.config / name).read_bytes(), before["config/" + name])
        data = json.loads((self.config / "omarchy/shell.json").read_text())
        self.assertEqual(data["bar"]["layout"], {"right": ["omarchy.keyboard", "omarchy.clock"], "left": ["other.widget"]})
        self.assertEqual(data["plugins"], ["other.widget"])
        self.assertEqual(data["disabledPlugins"], ["other.disabled"])
        self.assertEqual(data["personal"], {"keep": True})
        self.assertTrue(list((self.config / "hypr").glob("hyprland.lua.bak.*")))
        archive, = (self.config / "omarchy/plugins").glob("*.tar.gz")
        with tarfile.open(archive) as saved:
            self.assertEqual(saved.extractfile(PLUGIN + "/ImStatus.qml").read(), b"// user-tuned widget\n")
        after = self.snapshot()
        self.assertEqual(self.run_uninstall().returncode, 0)
        self.assertEqual(after, self.snapshot(), "second run must not rewrite files or add backups")

    def test_custom_shared_files_are_preserved(self):
        custom = {"config/environment.d/fcitx.conf": ENVIRONMENT + "CUSTOM=1\n", "config/autostart/org.fcitx.Fcitx5.desktop": "[Desktop Entry]\nHidden=false\n", "bin/omarchy-latin-launch": "#!/bin/bash\necho personal\n"}
        for name, text in custom.items():
            self.put(name, text)
        result = self.run_uninstall()
        self.assertEqual(result.returncode, 0, result.stderr)
        for name, text in custom.items():
            self.assertEqual((self.root / name).read_text(), text)

    def test_old_system_keeps_environment_but_removes_owned_autostart(self):
        (self.stock / "default/environment.d/10-omarchy-fcitx.conf").unlink()
        (self.stock / "config/autostart/org.fcitx.Fcitx5.desktop").unlink()
        result = self.run_uninstall()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.config / "environment.d/fcitx.conf").exists())
        self.assertFalse((self.config / "autostart/org.fcitx.Fcitx5.desktop").exists())

    def test_broken_marker_does_not_delete_unrelated_lua(self):
        self.put("config/hypr/hyprland.lua", '-- setup-korean:begin\n-- important user settings\n')
        before = self.snapshot()
        result = self.run_uninstall()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(before, self.snapshot())

    def test_legacy_binding_keeps_wrapper(self):
        self.put("config/hypr/bindings.lua", 'o.bind("SUPER + SPACE", "menu", "omarchy-latin-launch omarchy-menu")\n')
        result = self.run_uninstall()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.bin / "omarchy-latin-launch").exists())
        self.assertIn("수동 정리", result.stderr)

    def test_reload_validates_errors_and_rescans_plugins(self):
        commands = self.root / "calls"
        fakebin = self.root / "fakebin"
        for name in ("hyprctl", "omarchy-shell"):
            stub = self.put("fakebin/" + name, '#!/bin/bash\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$CALLS"\n')
            stub.chmod(0o755)
        self.env.update(PATH=str(fakebin) + os.pathsep + os.environ["PATH"], CALLS=str(commands))
        result = self.run_uninstall(reload=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(commands.read_text().splitlines(), ["hyprctl reload", "hyprctl configerrors", "omarchy-shell shell rescanPlugins"])

    def test_no_fcitx_restore_option(self):
        before = self.snapshot()
        result = self.run_uninstall("--fcitx")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(before, self.snapshot())


if __name__ == "__main__":
    unittest.main()
