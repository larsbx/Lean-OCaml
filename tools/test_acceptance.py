#!/usr/bin/env python3
"""Regression checks for portable, fail-closed source receipts."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import acceptance


class SourceReceiptTests(unittest.TestCase):
    def snapshot(self, root: Path):
        with patch.object(acceptance, "ROOT", root), patch.object(
            acceptance, "EVIDENCE", root / "conformance/evidence"
        ):
            return acceptance.source_snapshot()

    def test_checkout_and_worktree_metadata_give_same_source_digest(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "source.ml").write_text("let answer = 42\n")
            (root / ".gitattributes").write_text("*.ml text\n")
            expected = self.snapshot(root)
            self.assertEqual(
                [entry["path"] for entry in expected[0]],
                [".gitattributes", "source.ml"],
            )
            metadata = root / ".git"
            metadata.mkdir()
            (metadata / "config").write_text("private checkout metadata\n")
            self.assertEqual(self.snapshot(root), expected)
            (metadata / "config").unlink()
            metadata.rmdir()
            metadata.write_text("gitdir: /another/local/path/worktrees/review\n")
            self.assertEqual(self.snapshot(root), expected)

    def test_source_directory_symlink_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "source").mkdir()
            (root / "alias").symlink_to(root / "source", target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "source directory symlink"):
                self.snapshot(root)

    def test_source_file_symlink_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "source.ml").write_text("let answer = 42\n")
            (root / "alias.ml").symlink_to(root / "source.ml")
            with self.assertRaisesRegex(ValueError, "source symlink"):
                self.snapshot(root)


if __name__ == "__main__":
    unittest.main()
