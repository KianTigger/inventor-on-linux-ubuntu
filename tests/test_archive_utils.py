from __future__ import annotations

import tempfile
import zipfile
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "windows_bridge"))

from archive_utils import find_root_iam, safe_extract_zip


def test_root_iam_prefers_shallow_then_large() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "root.iam").write_bytes(b"x" * 10)
        (root / "sub").mkdir()
        (root / "sub" / "large.iam").write_bytes(b"x" * 100)
        assert find_root_iam(root).name == "root.iam"


def test_zip_slip_is_rejected() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        archive = root / "bad.zip"
        with zipfile.ZipFile(archive, "w") as zf:
            zf.writestr("../escape.ipt", b"bad")
        try:
            safe_extract_zip(archive, root / "out")
        except ValueError:
            return
        raise AssertionError("zip-slip entry was not rejected")


if __name__ == "__main__":
    test_root_iam_prefers_shallow_then_large()
    test_zip_slip_is_rejected()
    print("archive_utils tests passed")
