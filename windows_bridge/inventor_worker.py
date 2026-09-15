from __future__ import annotations

import queue
import threading
import traceback
from concurrent.futures import Future
from pathlib import Path
from typing import Any, Callable

import pythoncom
import win32com.client

from config import settings

MIN_VALID_EXPORT_BYTES = 500


class InventorWorker:
    """Serialize every Inventor COM call onto one dedicated STA thread."""

    def __init__(self) -> None:
        self._queue: queue.Queue[tuple[Future, Callable[..., Any], tuple, dict] | None] = queue.Queue()
        self._thread = threading.Thread(target=self._run, name="InventorCOM", daemon=True)
        self._started = threading.Event()
        self._startup_error: BaseException | None = None
        self._inventor = None
        self._started_inventor = False

    def start(self) -> None:
        self._thread.start()
        self._started.wait(timeout=15)
        if self._startup_error:
            raise RuntimeError(f"Inventor COM worker failed to start: {self._startup_error}") from self._startup_error
        if not self._thread.is_alive():
            raise RuntimeError("Inventor COM worker stopped during startup.")

    def stop(self) -> None:
        self._queue.put(None)
        self._thread.join(timeout=10)

    @property
    def alive(self) -> bool:
        return self._thread.is_alive()

    def submit(self, fn: Callable[..., Any], *args: Any, **kwargs: Any) -> Future:
        future: Future = Future()
        self._queue.put((future, fn, args, kwargs))
        return future

    def _run(self) -> None:
        try:
            pythoncom.CoInitializeEx(pythoncom.COINIT_APARTMENTTHREADED)
            self._started.set()
            while True:
                try:
                    item = self._queue.get(timeout=0.25)
                except queue.Empty:
                    pythoncom.PumpWaitingMessages()
                    continue
                if item is None:
                    break
                future, fn, args, kwargs = item
                if future.cancelled():
                    continue
                try:
                    result = fn(*args, **kwargs)
                except BaseException as exc:
                    future.set_exception(exc)
                else:
                    future.set_result(result)
                finally:
                    pythoncom.PumpWaitingMessages()
        except BaseException as exc:
            self._startup_error = exc
            self._started.set()
        finally:
            if settings.quit_on_exit and self._inventor is not None and self._started_inventor:
                try:
                    self._inventor.Quit()
                except Exception:
                    pass
            self._inventor = None
            try:
                pythoncom.CoUninitialize()
            except Exception:
                pass

    def _get_inventor(self):
        if self._inventor is not None:
            try:
                _ = self._inventor.Documents.Count
                return self._inventor
            except Exception:
                self._inventor = None

        try:
            inventor = win32com.client.GetActiveObject("Inventor.Application")
            self._started_inventor = False
        except Exception:
            if not settings.start_if_needed:
                raise RuntimeError(
                    "Inventor is not running and INVENTOR_START_IF_NEEDED=false."
                )
            inventor = win32com.client.Dispatch("Inventor.Application")
            self._started_inventor = True

        inventor.Visible = settings.inventor_visible
        try:
            inventor.SilentOperation = True
        except Exception:
            pass
        self._inventor = inventor
        return inventor

    def status(self) -> dict[str, Any]:
        inventor = self._get_inventor()
        version = "unknown"
        try:
            version = str(inventor.SoftwareVersion.DisplayVersion)
        except Exception:
            try:
                version = str(inventor.SoftwareVersion)
            except Exception:
                pass
        return {
            "inventor_connected": True,
            "inventor_version": version,
            "inventor_visible": bool(settings.inventor_visible),
            "started_by_bridge": bool(self._started_inventor),
        }

    def extract(self, source_path: str, output_dir: str, original_name: str) -> dict[str, Any]:
        inventor = self._get_inventor()
        source = Path(source_path).resolve()
        output = Path(output_dir).resolve()
        output.mkdir(parents=True, exist_ok=True)
        stl_path = output / "model.stl"
        step_path = output / "model.step"

        for stale in (stl_path, step_path):
            try:
                stale.unlink(missing_ok=True)
            except Exception:
                pass

        doc = None
        try:
            options = inventor.TransientObjects.CreateNameValueMap()
            options.Add("SkipAllUnresolvedFiles", True)
            doc = inventor.Documents.OpenWithOptions(str(source), options)
            if not doc:
                raise RuntimeError(f"Inventor returned no document for {original_name}.")

            raw_iproperties: dict[str, dict[str, str]] = {}
            for prop_set in doc.PropertySets:
                set_values: dict[str, str] = {}
                for prop in prop_set:
                    try:
                        value = prop.Value
                        if value is not None:
                            set_values[str(prop.Name)] = str(value)
                    except Exception:
                        continue
                raw_iproperties[str(prop_set.Name)] = set_values

            part_number = Path(original_name).stem
            try:
                candidate = raw_iproperties.get("Design Tracking Properties", {}).get("Part Number")
                if candidate:
                    part_number = candidate
            except Exception:
                pass

            bounding_box = None
            try:
                comp_def = doc.ComponentDefinition
                range_box = comp_def.RangeBox
                min_pt = range_box.MinPoint
                max_pt = range_box.MaxPoint
                mass_props = comp_def.MassProperties
                bounding_box = {
                    "x_min": float(min_pt.X),
                    "x_max": float(max_pt.X),
                    "y_min": float(min_pt.Y),
                    "y_max": float(max_pt.Y),
                    "z_min": float(min_pt.Z),
                    "z_max": float(max_pt.Z),
                    "volume_cm3": float(mass_props.Volume),
                    "mass_kg": float(mass_props.Mass),
                    "surface_area_cm2": float(mass_props.Area),
                }
            except Exception:
                bounding_box = None

            doc.SaveAs(str(stl_path), True)
            doc.SaveAs(str(step_path), True)

            for exported in (stl_path, step_path):
                if not exported.is_file() or exported.stat().st_size < MIN_VALID_EXPORT_BYTES:
                    raise RuntimeError(
                        f"Inventor created an invalid {exported.suffix.upper()} export for {original_name}."
                    )

            return {
                "file_path": original_name,
                "part_number": str(part_number),
                "raw_iproperties": raw_iproperties,
                "bounding_box": bounding_box,
                "stl_path": "model.stl",
            }
        except Exception as exc:
            details = traceback.format_exc(limit=8)
            raise RuntimeError(f"Inventor extraction failed for {original_name}: {exc}\n{details}") from exc
        finally:
            if doc is not None:
                try:
                    doc.Close(True)
                except Exception:
                    pass
