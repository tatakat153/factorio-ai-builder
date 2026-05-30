"""
Factorio AI Builder - Bridge Service (FastAPI)

Agent-agnostic HTTP API that translates between AI agents and Factorio's RCON.
Runs locally, connects to Factorio via RCON over TCP.

Configuration: edit config.ini or set environment variables.

Usage:
    uvicorn main:app --host 0.0.0.0 --port 9380
    # or
    python main.py
"""

import asyncio
import configparser
import json
import logging
import os
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from rcon_client import RCONClient, create_rcon_client
from area_cache import AreaCache

# ============================================================================
# Configuration
# ============================================================================

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("bridge")


def load_config():
    """Load config from config.ini or environment variables."""
    cfg = configparser.ConfigParser()
    config_path = Path(__file__).parent / "config.ini"
    if config_path.exists():
        cfg.read(config_path)

    return {
        "rcon_host": os.environ.get("FACTORIO_RCON_HOST", cfg.get("factorio", "host", fallback="127.0.0.1")),
        "rcon_port": int(os.environ.get("FACTORIO_RCON_PORT", cfg.get("factorio", "port", fallback="34198"))),
        "rcon_password": os.environ.get("FACTORIO_RCON_PASSWORD", cfg.get("factorio", "password", fallback="factorio")),
        "bridge_host": os.environ.get("BRIDGE_HOST", cfg.get("bridge", "host", fallback="0.0.0.0")),
        "bridge_port": int(os.environ.get("BRIDGE_PORT", cfg.get("bridge", "port", fallback="9380"))),
    }


CONFIG = load_config()
RCON_HOST = CONFIG["rcon_host"]
RCON_PORT = CONFIG["rcon_port"]
RCON_PASSWORD = CONFIG["rcon_password"]
BRIDGE_HOST = CONFIG["bridge_host"]
BRIDGE_PORT = CONFIG["bridge_port"]

# ============================================================================
# Global State
# ============================================================================

rcon: Optional[RCONClient] = None
cache = AreaCache()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup/shutdown lifecycle. Tries to auto-connect to RCON."""
    global rcon
    logger.info("Bridge service starting...")
    try:
        rcon_client = RCONClient(RCON_HOST, RCON_PORT, RCON_PASSWORD)
        connected = await rcon_client.connect(timeout=3.0)
        if connected:
            rcon = rcon_client
            logger.info(f"Connected to Factorio RCON at {RCON_HOST}:{RCON_PORT}")
        else:
            logger.info("RCON not available. Use POST /api/v1/connect to connect later.")
            rcon = None
    except Exception as e:
        logger.info(f"RCON auto-connect skipped: {e}")
        rcon = None
    yield
    if rcon:
        try:
            await rcon.disconnect()
        except Exception:
            pass
    logger.info("Bridge service stopped")


app = FastAPI(
    title="Factorio AI Builder Bridge",
    version="0.2.0-beta",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============================================================================
# Helper
# ============================================================================

async def call(method: str, *args):
    """Call Factorio mod remote interface."""
    if not rcon:
        raise HTTPException(503, "RCON not connected. Use POST /connect first.")
    result = await rcon.remote_call("ai_builder", method, *args)
    return result


async def call_ok(method: str, *args):
    """Call and assert success."""
    result = await call(method, *args)
    if not result.get("success"):
        raise HTTPException(400, detail=result)
    return result.get("data")


# ============================================================================
# Pydantic Models
# ============================================================================

class Position(BaseModel):
    x: float
    y: float


class ConnectRequest(BaseModel):
    host: str = "127.0.0.1"
    port: int = 34198
    password: str = "factorio"


class CreateAgentRequest(BaseModel):
    position: Position = Position(x=0, y=0)


class WalkRequest(BaseModel):
    goal: Position
    strict_goal: bool = False


class SingleBuildRequest(BaseModel):
    entity_name: str
    position: Position
    direction: int = 0


class BatchBuildRequest(BaseModel):
    template_name: str
    anchor: Position
    count: int = 1
    recipe_name: Optional[str] = None
    obstacle_resolution: Optional[str] = None


class BatchResumeRequest(BaseModel):
    resolution: str = "skip_obstacles"


class MineRequest(BaseModel):
    resource_name: str
    max_count: int = 50
    position_hint: Optional[Position] = None


class MarkRequest(BaseModel):
    mark_id: str
    corner1: Position
    corner2: Position
    label: str = ""


class RecipeRequest(BaseModel):
    entity_name: str
    position: Position
    recipe_name: str


class InventoryRequest(BaseModel):
    entity_name: str
    position: Position
    item_name: str
    count: int = 0
    inv_type: Optional[str] = None


class CraftRequest(BaseModel):
    recipe_name: str
    count: int = 1


class ResearchRequest(BaseModel):
    technology_name: str


class PickupRequest(BaseModel):
    entity_ref: Any = None  # str (name) or int (unit_number)
    position: Optional[Position] = None


# ============================================================================
# API Endpoints
# ============================================================================

# --- Health ---

@app.get("/api/v1/health")
async def health():
    global rcon
    return {
        "connected": rcon is not None and rcon.client is not None,
        "host": RCON_HOST,
        "port": RCON_PORT,
    }


@app.post("/api/v1/connect")
async def connect(req: ConnectRequest):
    global rcon, RCON_HOST, RCON_PORT, RCON_PASSWORD
    RCON_HOST = req.host
    RCON_PORT = req.port
    RCON_PASSWORD = req.password
    rcon = await create_rcon_client(req.host, req.port, req.password)
    return {"connected": True}


# --- Agent ---

@app.post("/api/v1/agent/create")
async def create_agent(req: CreateAgentRequest):
    return await call_ok("create_agent", {"x": req.position.x, "y": req.position.y})


@app.post("/api/v1/agent/destroy")
async def destroy_agent():
    return await call_ok("destroy_agent")


@app.get("/api/v1/agent/state")
async def agent_state():
    return await call_ok("get_agent_state")


@app.post("/api/v1/agent/give-items")
async def give_items(req: InventoryRequest):
    """Give items to agent (for testing). Uses character inventory."""
    return await call_ok("give_items", req.item_name, req.count)


@app.get("/api/v1/agent/inventory")
async def agent_inventory():
    return await call_ok("get_inventory")


# --- Movement ---

@app.post("/api/v1/agent/walk/approach")
async def approach(req: WalkRequest):
    """Walk to within build distance of a target (for mining/placing)."""
    result = await call("approach_to", {"x": req.goal.x, "y": req.goal.y})
    if result.get("success"):
        return {"queued": True, "action_id": f"approach_{int(time.time()*1000)}", "detail": result["data"]}
    raise HTTPException(400, detail=result)


@app.post("/api/v1/agent/walk")
async def walk(req: WalkRequest):
    result = await call("walk_to", {"x": req.goal.x, "y": req.goal.y}, req.strict_goal)
    if result.get("success"):
        data = result["data"]
        return {"queued": True, "action_id": f"walk_{int(time.time()*1000)}", "detail": data}
    raise HTTPException(400, detail=result)


@app.get("/api/v1/agent/walk/status")
async def walk_status():
    """Poll movement status."""
    return await call_ok("get_movement_status")


@app.post("/api/v1/agent/stop")
async def stop_moving():
    return await call_ok("stop_moving")


# --- Single Placement ---

@app.post("/api/v1/agent/build/single")
async def build_single(req: SingleBuildRequest):
    return await call_ok("place_entity", req.entity_name,
                         {"x": req.position.x, "y": req.position.y},
                         req.direction)


@app.post("/api/v1/agent/pickup")
async def pickup(req: PickupRequest):
    return await call_ok("pickup_entity", req.entity_ref,
                         {"x": req.position.x, "y": req.position.y} if req.position else nil_arg())


@app.post("/api/v1/agent/recipe")
async def set_recipe(req: RecipeRequest):
    return await call_ok("set_entity_recipe", req.entity_name,
                         {"x": req.position.x, "y": req.position.y},
                         req.recipe_name)


# --- Mining ---

@app.post("/api/v1/agent/mine")
async def mine(req: MineRequest):
    hint = {"x": req.position_hint.x, "y": req.position_hint.y} if req.position_hint else None
    result = await call("mine_resource", req.resource_name, req.max_count, hint)
    if result.get("success"):
        data = result["data"]
        return {"queued": True, "action_id": f"mine_{int(time.time()*1000)}", "detail": data}
    raise HTTPException(400, detail=result)


# --- Inventory ---

@app.post("/api/v1/agent/insert")
async def insert_items(req: InventoryRequest):
    return await call_ok("insert_items", req.entity_name,
                         {"x": req.position.x, "y": req.position.y},
                         req.item_name, req.count, req.inv_type)


@app.post("/api/v1/agent/extract")
async def extract_items(req: InventoryRequest):
    return await call_ok("extract_items", req.entity_name,
                         {"x": req.position.x, "y": req.position.y},
                         req.item_name, req.count, req.inv_type)


# --- Crafting ---

@app.post("/api/v1/agent/craft")
async def craft(req: CraftRequest):
    return await call_ok("craft_enqueue", req.recipe_name, req.count)


@app.post("/api/v1/agent/craft/cancel")
async def cancel_craft(req: CraftRequest):
    return await call_ok("cancel_crafting", req.recipe_name, req.count)


@app.get("/api/v1/agent/craft/queue")
async def craft_queue():
    return await call_ok("get_crafting_queue")


# --- Research ---

@app.get("/api/v1/technologies")
async def technologies(only_available: bool = False):
    return await call_ok("get_technologies", only_available)


@app.post("/api/v1/research/enqueue")
async def enqueue_research(req: ResearchRequest):
    return await call_ok("enqueue_research", req.technology_name)


@app.post("/api/v1/research/cancel")
async def cancel_research():
    return await call_ok("cancel_research")


@app.get("/api/v1/research/current")
async def current_research():
    return await call_ok("get_current_research")


# --- Area Query ---

@app.get("/api/v1/world/overview")
async def overview(center_x: float = 0, center_y: float = 0, radius_chunks: int = 3):
    return await call_ok("get_overview", {"x": center_x, "y": center_y}, radius_chunks)


@app.post("/api/v1/world/mark")
async def create_mark(req: MarkRequest):
    result = await call_ok("create_mark", req.mark_id,
                           {"x": req.corner1.x, "y": req.corner1.y},
                           {"x": req.corner2.x, "y": req.corner2.y},
                           req.label)
    # Add to local cache
    cache.add(req.mark_id, req.corner1, req.corner2, req.label)
    return result


@app.get("/api/v1/world/mark/{mark_id}")
async def get_mark_detail(mark_id: str):
    result = await call_ok("get_mark_detail", mark_id)
    cache.update_detail(mark_id, result)
    return result


@app.delete("/api/v1/world/mark/{mark_id}")
async def remove_mark(mark_id: str):
    cache.remove(mark_id)
    return await call_ok("remove_mark", mark_id)


@app.get("/api/v1/world/marks")
async def list_marks():
    return await call_ok("list_marks")


# --- Batch Build ---

@app.post("/api/v1/agent/build/batch")
async def build_batch(req: BatchBuildRequest):
    options = {}
    if req.recipe_name:
        options["recipe_name"] = req.recipe_name
    if req.obstacle_resolution:
        options["obstacle_resolution"] = req.obstacle_resolution

    result = await call("batch_build", req.template_name,
                        {"x": req.anchor.x, "y": req.anchor.y},
                        req.count, options)
    if result.get("success"):
        return result["data"]
    raise HTTPException(400, detail=result)


@app.get("/api/v1/agent/build/batch/{batch_id}")
async def get_batch_status(batch_id: str):
    return await call_ok("get_batch_status", batch_id)


@app.post("/api/v1/agent/build/batch/{batch_id}/resume")
async def resume_batch(batch_id: str, req: BatchResumeRequest):
    result = await call("resume_batch", batch_id, req.resolution)
    if result.get("success"):
        return result["data"]
    raise HTTPException(400, detail=result)


@app.post("/api/v1/agent/build/batch/{batch_id}/cancel")
async def cancel_batch(batch_id: str):
    return await call_ok("cancel_batch", batch_id)


# --- Emergency ---

@app.post("/api/v1/emergency-stop")
async def emergency_stop():
    return await call_ok("emergency_stop")


@app.post("/api/v1/emergency-reset")
async def emergency_reset():
    return await call_ok("reset_emergency")


# --- Templates & Recipes ---

@app.get("/api/v1/templates")
async def list_templates():
    return await call_ok("list_templates")


@app.get("/api/v1/recipes")
async def get_recipes():
    return await call_ok("get_recipes")


# --- Helper ---

def nil_arg():
    """Return Python None, which maps to Lua nil in our serializer."""
    return None


if __name__ == "__main__":
    import uvicorn
    logger.info(f"Starting bridge on {BRIDGE_HOST}:{BRIDGE_PORT}")
    logger.info(f"RCON target: {RCON_HOST}:{RCON_PORT}")
    uvicorn.run(app, host=BRIDGE_HOST, port=BRIDGE_PORT, log_level="info")
