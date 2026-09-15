from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env")


def _bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    bind: str = os.getenv("INVENTOR_BRIDGE_BIND", "0.0.0.0")
    port: int = int(os.getenv("INVENTOR_BRIDGE_PORT", "8765"))
    token: str = os.getenv("INVENTOR_BRIDGE_TOKEN", "").strip()
    inventor_visible: bool = _bool("INVENTOR_VISIBLE", True)
    start_if_needed: bool = _bool("INVENTOR_START_IF_NEEDED", True)
    quit_on_exit: bool = _bool("INVENTOR_QUIT_ON_BRIDGE_EXIT", False)
    max_upload_mb: int = int(os.getenv("INVENTOR_MAX_UPLOAD_MB", "250"))

    def validate(self) -> None:
        if not self.token or self.token == "CHANGE_ME" or len(self.token) < 24:
            raise RuntimeError(
                "INVENTOR_BRIDGE_TOKEN must be configured with a random value of at least 24 characters."
            )
        if not (1 <= self.port <= 65535):
            raise RuntimeError("INVENTOR_BRIDGE_PORT must be between 1 and 65535.")
        if self.max_upload_mb < 1:
            raise RuntimeError("INVENTOR_MAX_UPLOAD_MB must be positive.")


settings = Settings()
settings.validate()
