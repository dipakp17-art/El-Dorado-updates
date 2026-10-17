"""Read-only checks for El Dorado's update metadata and download pages."""
import json
import re
import unittest
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]


class PageParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if "id" in attributes:
            self.ids.add(attributes["id"])


class RepositoryTests(unittest.TestCase):
    def test_release_metadata(self):
        data = json.loads((ROOT / "app.json").read_text(encoding="utf-8"))
        self.assertIsInstance(data["versionCode"], int)
        self.assertGreater(data["versionCode"], 0)
        self.assertRegex(data["versionName"], r"^\d+\\.\d+(?:\\.\d+)?$")
        self.assertGreater(data["size"], 0)
        self.assertRegex(data["sha256"], r"^[0-9a-fA-F]{64}$")
        url = urlparse(data["apk"])
        self.assertEqual(url.scheme, "https")
        self.assertEqual(url.netloc, "raw.githubusercontent.com")
        self.assertTrue(url.path.startswith("/dipakp17-art/El-Dorado-updates/main/"))
        self.assertRegex(url.path, r"/El-Dorado-\d+\\.apk$")
        self.assertTrue(url.path.endswith(f"/El-Dorado-{data['versionCode']}.apk"))

    def test_download_page_elements(self):
        parser = PageParser()
        parser.feed((ROOT / "index.html").read_text(encoding="utf-8"))
        self.assertTrue({"dl", "ver"}.issubset(parser.ids))

    def test_invitation_page_elements(self):
        parser = PageParser()
        parser.feed((ROOT / "add.html").read_text(encoding="utf-8"))
        self.assertTrue({"title", "sub", "id", "open", "get"}.issubset(parser.ids))


if __name__ == "__main__":
    unittest.main()
