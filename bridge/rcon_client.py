"""
Factorio AI Builder - RCON Client
Handles communication with Factorio game server via RCON protocol.

Uses factorio-rcon-py (sync API) wrapped in asyncio thread pool.
"""

import asyncio
import json
import logging
import math
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Optional

try:
    import factorio_rcon
except ImportError:
    factorio_rcon = None
    logging.warning("factorio-rcon-py not installed. Install with: pip install factorio-rcon-py")

logger = logging.getLogger(__name__)


class RCONClient:
    """Wrapper around factorio-rcon-py (sync) with JSON response parsing."""

    def __init__(self, host: str = "127.0.0.1", port: int = 34198, password: str = "factorio"):
        self.host = host
        self.port = port
        self.password = password
        self.client: Optional[Any] = None
        self._executor = ThreadPoolExecutor(max_workers=1)

    async def connect(self, timeout: float = 5.0) -> bool:
        """Establish RCON connection (sync, run in thread)."""
        if factorio_rcon is None:
            raise RuntimeError("factorio-rcon-py not installed")

        def _connect():
            client = factorio_rcon.RCONClient(self.host, self.port, self.password)
            client.connect()
            result = client.send_command("/c game.print('ai_builder_rcon_ok')")
            return client, result

        try:
            self.client, result = await asyncio.wait_for(
                asyncio.get_event_loop().run_in_executor(self._executor, _connect),
                timeout=timeout
            )
            logger.info(f"RCON connected to {self.host}:{self.port}")
            return True
        except asyncio.TimeoutError:
            logger.error(f"RCON connection timeout ({timeout}s)")
            self.client = None
            return False
        except Exception as e:
            logger.error(f"RCON connection failed: {e}")
            self.client = None
            return False

    async def disconnect(self):
        """Close RCON connection."""
        if self.client:
            def _close():
                try:
                    self.client.close()
                except Exception:
                    pass

            try:
                await asyncio.get_event_loop().run_in_executor(self._executor, _close)
            except Exception:
                pass
            self.client = None
            self._executor.shutdown(wait=False)

    async def _send_command(self, command: str) -> Optional[str]:
        """Send a raw command via RCON (sync, run in thread)."""
        if not self.client:
            raise ConnectionError("RCON not connected")

        def _send():
            return self.client.send_command(command)

        return await asyncio.get_event_loop().run_in_executor(self._executor, _send)

    async def remote_call(self, interface: str, method: str, *args) -> dict:
        """
        Call a Factorio mod remote interface method.
        Returns parsed JSON response dict with {success, data} or {success, error, detail}
        """
        lua_args = self._serialize_args(args)
        command = (
            f"/c rcon.print(helpers.table_to_json("
            f"remote.call(\"{interface}\", \"{method}\"{lua_args})))"
        )

        try:
            response = await self._send_command(command)
            return self._parse_json_response(response or "")
        except Exception as e:
            logger.error(f"RCON command failed: {method} - {e}")
            return {"success": False, "error": "rcon_error", "detail": str(e)}

    def _serialize_args(self, args: tuple) -> str:
        """Convert Python arguments to Lua function argument string."""
        if not args:
            return ""

        parts = []
        for arg in args:
            parts.append(self._serialize_value(arg))

        return ", " + ", ".join(parts)

    def _serialize_value(self, value: Any) -> str:
        """Convert a Python value to Lua literal."""
        if value is None:
            return "nil"
        elif isinstance(value, bool):
            return "true" if value else "false"
        elif isinstance(value, (int, float)):
            if value != value:
                return "0/0"
            if value == math.inf:
                return "math.huge"
            if value == -math.inf:
                return "-math.huge"
            return repr(value)
        elif isinstance(value, str):
            escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
            return f'"{escaped}"'
        elif isinstance(value, (list, tuple)):
            items = [self._serialize_value(v) for v in value]
            return "{" + ", ".join(items) + "}"
        elif isinstance(value, dict):
            items = []
            for k, v in value.items():
                key_str = f'["{k}"]' if isinstance(k, str) else f"[{k}]"
                items.append(f"{key_str} = {self._serialize_value(v)}")
            return "{" + ", ".join(items) + "}"
        else:
            return f'"{str(value)}"'

    def _parse_json_response(self, response: str) -> dict:
        """Parse JSON response from Factorio's rcon.print output."""
        if not response or not response.strip():
            return {"success": False, "error": "empty_response"}

        response = response.strip()
        start = response.find("{")
        if start == -1:
            return {"success": False, "error": "no_json_found", "raw": response[:500]}

        json_str = response[start:]
        depth = 0
        end = -1
        in_string = False
        escape_next = False

        for i, ch in enumerate(json_str):
            if escape_next:
                escape_next = False
                continue
            if ch == "\\":
                escape_next = True
                continue
            if ch == '"' and not escape_next:
                in_string = not in_string
                continue
            if in_string:
                continue
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = i + 1
                    break

        if end == -1:
            return {"success": False, "error": "malformed_json", "raw": json_str[:500]}

        try:
            return json.loads(json_str[:end])
        except json.JSONDecodeError as e:
            logger.warning(f"JSON parse error: {e}")
            return {"success": False, "error": "json_parse_error", "detail": str(e)}


async def create_rcon_client(host: str, port: int, password: str) -> RCONClient:
    """Factory function: create and connect an RCON client."""
    client = RCONClient(host, port, password)
    connected = await client.connect()
    if not connected:
        raise ConnectionError(f"Failed to connect to Factorio RCON at {host}:{port}")
    return client
