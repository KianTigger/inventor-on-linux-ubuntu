from __future__ import annotations

import uvicorn

from config import settings

if __name__ == "__main__":
    uvicorn.run(
        "server:app",
        host=settings.bind,
        port=settings.port,
        reload=False,
        log_level="info",
    )
