"""
Factorio AI Builder - Area Cache
Sparse spatial index maintained by AI. Marks expire after TTL.
"""

import time
import logging
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)


class AreaCache:
    """AI-maintained sparse cache of marked areas."""

    def __init__(self, ttl: int = 300):
        self.marks: Dict[str, dict] = {}
        self.ttl = ttl  # seconds

    def add(self, mark_id: str, corner1, corner2, label: str = ""):
        """Add or update a mark in cache."""
        self.marks[mark_id] = {
            "corner1": {"x": corner1.x, "y": corner1.y},
            "corner2": {"x": corner2.x, "y": corner2.y},
            "label": label,
            "detail": None,
            "cached_at": time.time(),
            "accessed_at": time.time(),
        }
        logger.debug(f"Cache: added mark {mark_id}")

    def update_detail(self, mark_id: str, detail: dict):
        """Update cached detail for a mark."""
        if mark_id in self.marks:
            self.marks[mark_id]["detail"] = detail
            self.marks[mark_id]["accessed_at"] = time.time()

    def remove(self, mark_id: str):
        """Remove a mark from cache."""
        self.marks.pop(mark_id, None)
        logger.debug(f"Cache: removed mark {mark_id}")

    def get(self, mark_id: str) -> Optional[dict]:
        """Get cached mark if not expired."""
        mark = self.marks.get(mark_id)
        if mark is None:
            return None

        if time.time() - mark["cached_at"] > self.ttl:
            self.marks.pop(mark_id)
            return None

        mark["accessed_at"] = time.time()
        return mark

    def get_stale_marks(self) -> list:
        """Return list of expired mark IDs (for AI cleanup hint)."""
        now = time.time()
        stale = []
        for mark_id, mark in list(self.marks.items()):
            if now - mark["cached_at"] > self.ttl:
                stale.append(mark_id)
        return stale

    def list_marks(self) -> list:
        """List all cached marks with basic info."""
        result = []
        for mark_id, mark in self.marks.items():
            result.append({
                "mark_id": mark_id,
                "label": mark["label"],
                "corner1": mark["corner1"],
                "corner2": mark["corner2"],
                "cached_at": mark["cached_at"],
            })
        return result

    def cleanup(self):
        """Remove all expired marks."""
        now = time.time()
        expired = [mid for mid, m in self.marks.items()
                   if now - m["cached_at"] > self.ttl]
        for mid in expired:
            self.marks.pop(mid)
        if expired:
            logger.info(f"Cache: cleaned up {len(expired)} expired marks")
