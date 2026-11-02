import json
import pathlib
import subprocess
import tempfile
import unittest
from render import HERE, render


class PrivateDeploymentTests(unittest.TestCase):
    def setUp(self):
        self.config = json.loads((HERE / "local.example.json").read_text())

    def test_rendered_files_are_complete_private_and_valid_shell(self):
        with tempfile.TemporaryDirectory() as directory:
            render(self.config, directory)
            files = list(pathlib.Path(directory).iterdir())
            self.assertEqual(len(files), 5)
            for path in files:
                self.assertNotIn("@@", path.read_text())
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            for name in ["activate-public.sh", "moneytrack-firewall", "prepare-host.sh"]:
                subprocess.run(["sh", "-n", str(pathlib.Path(directory) / name)], check=True)
            nginx = (pathlib.Path(directory) / "nginx-moneytrack.conf").read_text()
            self.assertIn("server_name app.example.invalid;", nginx)
            self.assertIn("listen [2001:db8::10]:443 ssl;", nginx)

    def test_invalid_host_and_address_settings_are_rejected(self):
        for key, value in [("PUBLIC_HOST", "bad;hostname"), ("APP_IP", "not-an-ip"),
                           ("PROXY_IPV6", "127.0.0.1"), ("APP_SSH", "host;command")]:
            with self.subTest(key=key), tempfile.TemporaryDirectory() as directory:
                config = dict(self.config, **{key: value})
                with self.assertRaises(ValueError):
                    render(config, directory)

    def test_output_cannot_be_written_to_a_tracked_source_directory(self):
        with self.assertRaises(ValueError):
            render(self.config, HERE / "templates")


if __name__ == "__main__":
    unittest.main()
