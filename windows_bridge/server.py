from __future__ import annotations

import asyncio
import json
import shutil
import tempfile
import zipfile
from pathlib import Path

from fastapi import Depends, FastAPI, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse
from starlette.background import BackgroundTask

from archive_utils import prepare_source, safe_rmtree
from config import settings
from inventor_worker import InventorWorker

app = FastAPI(title="Inventor VM Bridge", version="1.0.0", docs_url="/docs")
worker = InventorWorker()


async def require_token(x_inventor_bridge_token: str | None = Header(default=None)) -> None:
    if x_inventor_bridge_token != settings.token:
        raise HTTPException(status_code=401, detail="Invalid Inventor bridge token.")


@app.on_event("startup")
def startup() -> None:
    worker.start()


@app.on_event("shutdown")
def shutdown() -> None:
    worker.stop()


@app.get("/health")
def health() -> dict:
    return {"status": "ready" if worker.alive else "error", "worker_alive": worker.alive}


@app.get("/v1/status", dependencies=[Depends(require_token)])
async def status() -> dict:
    try:
        return await asyncio.wrap_future(worker.submit(worker.status))
    except Exception as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


async def _save_upload(upload: UploadFile, destination: Path) -> None:
    max_bytes = settings.max_upload_mb * 1024 * 1024
    total = 0
    with destination.open("wb") as handle:
        while True:
            chunk = await upload.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > max_bytes:
                raise HTTPException(
                    status_code=413,
                    detail=f"Upload exceeds INVENTOR_MAX_UPLOAD_MB={settings.max_upload_mb} MB.",
                )
            handle.write(chunk)
    if total == 0:
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")


@app.post("/v1/extract", dependencies=[Depends(require_token)])
async def extract(file: UploadFile) -> FileResponse:
    if not file.filename:
        raise HTTPException(status_code=400, detail="A CAD filename is required.")

    work_dir = Path(tempfile.mkdtemp(prefix="inventor_bridge_"))
    try:
        input_dir = work_dir / "input"
        output_dir = work_dir / "output"
        input_dir.mkdir(parents=True, exist_ok=True)
        output_dir.mkdir(parents=True, exist_ok=True)

        safe_name = Path(file.filename).name
        upload_path = input_dir / safe_name
        await _save_upload(file, upload_path)
        source_path, source_name = prepare_source(upload_path, input_dir)

        try:
            metadata = await asyncio.wrap_future(
                worker.submit(worker.extract, str(source_path), str(output_dir), source_name)
            )
        except Exception as exc:
            raise HTTPException(status_code=500, detail=str(exc)) from exc

        metadata_path = output_dir / "metadata.json"
        metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")

        manifest = {
            "bridge_version": "1.0.0",
            "uploaded_name": safe_name,
            "inventor_source_name": source_name,
        }
        (output_dir / "bridge.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

        archive_path = work_dir / "result.zip"
        with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for name in ("metadata.json", "model.stl", "model.step", "bridge.json"):
                archive.write(output_dir / name, arcname=name)

        return FileResponse(
            archive_path,
            media_type="application/zip",
            filename=f"{Path(safe_name).stem}-inventor-result.zip",
            background=BackgroundTask(safe_rmtree, work_dir),
        )
    except HTTPException:
        safe_rmtree(work_dir)
        raise
    except Exception as exc:
        safe_rmtree(work_dir)
        raise HTTPException(status_code=500, detail=str(exc)) from exc
