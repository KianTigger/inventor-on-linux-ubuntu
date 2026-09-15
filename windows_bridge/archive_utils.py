from __future__ import annotations

import os
import shutil
import zipfile
from pathlib import Path

ALLOWED_INPUT_EXTENSIONS = {".ipt", ".iam", ".step", ".stp", ".zip"}


def safe_extract_zip(zip_path: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    root = destination.resolve()
    with zipfile.ZipFile(zip_path, "r") as archive:
        for member in archive.infolist():
            member_path = (destination / member.filename).resolve()
            if os.path.commonpath([str(root), str(member_path)]) != str(root):
                raise ValueError(f"Unsafe ZIP member path: {member.filename}")
        archive.extractall(destination)


def find_root_iam(folder: Path) -> Path:
    candidates: list[tuple[int, int, Path]] = []
    for path in folder.rglob("*"):
        if path.is_file() and path.suffix.lower() == ".iam":
            relative = path.relative_to(folder)
            depth = len(relative.parts) - 1
            candidates.append((depth, -path.stat().st_size, path))
    if not candidates:
        raise ValueError("The uploaded ZIP does not contain an .iam assembly file.")
    candidates.sort()
    return candidates[0][2]


def prepare_source(upload_path: Path, work_dir: Path) -> tuple[Path, str]:
    ext = upload_path.suffix.lower()
    if ext not in ALLOWED_INPUT_EXTENSIONS:
        raise ValueError(
            f"Unsupported CAD file type '{ext}'. Expected IPT, IAM, STEP, STP, or ZIP."
        )
    if ext != ".zip":
        return upload_path, upload_path.name

    extracted = work_dir / "bundle"
    safe_extract_zip(upload_path, extracted)
    root_iam = find_root_iam(extracted)
    return root_iam, root_iam.name


def safe_rmtree(path: Path) -> None:
    try:
        shutil.rmtree(path, ignore_errors=True)
    except Exception:
        pass
