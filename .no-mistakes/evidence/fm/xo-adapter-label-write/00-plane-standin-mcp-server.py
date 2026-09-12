#!/usr/bin/env python3
"""Stand-in Plane MCP server for live CLI driving.

Models one Plane project's label vocabulary as a JSON file on disk so the label
store survives across separate `fm-plane.py` invocations (each invocation spawns
its own stdio server process, exactly as a real home would connect to Plane).

Env:
  PLANE_STORE         path to the JSON label store (required)
  PLANE_PAGE_SIZE     labels returned per list page (default 2, to force paging)
  PLANE_REJECT_CREATE when "1", the server refuses label/create like a
                      read-only-token home would
  PLANE_RIVAL         when set, another home is simulated as having created a
                      label of that name in the window between this caller's
                      listing and its own create
"""
import fcntl
import json
import os
import uuid
from pathlib import Path

from mcp.server.fastmcp import FastMCP

STORE = Path(os.environ["PLANE_STORE"])
PAGE_SIZE = int(os.environ.get("PLANE_PAGE_SIZE", "2"))
REJECT_CREATE = os.environ.get("PLANE_REJECT_CREATE") == "1"
RIVAL = os.environ.get("PLANE_RIVAL", "")
CALL_LOG = os.environ.get("PLANE_CALL_LOG", "")


def log(tool, action, **rest):
    if CALL_LOG:
        with open(CALL_LOG, "a") as handle:
            handle.write(json.dumps({"tool": tool, "action": action, **rest}) + "\n")

server = FastMCP("plane-standin")


def load():
    return json.loads(STORE.read_text())


def save(labels):
    STORE.write_text(json.dumps(labels, indent=2) + "\n")


@server.tool()
def label(action: str, project_id: str = "", name: str = "",
          cursor: str | None = None, per_page: int = 100) -> dict:
    log("label", action, name=name)
    labels = load()
    if action == "create":
        if REJECT_CREATE:
            raise ValueError("You do not have permission to create labels in this project")
        # Serialize the read-modify-write so two homes creating at once both land,
        # the way a real Plane server would.
        with open(STORE, "r+") as handle:
            fcntl.flock(handle, fcntl.LOCK_EX)
            labels = json.load(handle)
            if RIVAL:
                labels.append({"id": f"lbl-rival-{uuid.uuid4().hex[:4]}", "name": RIVAL,
                               "project_id": project_id})
            entry = {"id": f"lbl-{uuid.uuid4().hex[:8]}", "name": name, "project_id": project_id}
            labels.append(entry)
            handle.seek(0)
            handle.truncate()
            json.dump(labels, handle, indent=2)
        return entry
    if action == "list":
        start = int(cursor.split(":")[1]) if cursor else 0
        end = start + PAGE_SIZE
        more = end < len(labels)
        return {"results": labels[start:end],
                "next_cursor": f"labels:{end}" if more else None,
                "next_page_results": more}
    raise ValueError("unsupported operation")


@server.tool()
def state(action: str, project_id: str = "") -> list[dict]:
    log("state", action)
    return [{"id": "state-backlog", "name": "Backlog", "group": "backlog"},
            {"id": "state-active", "name": "In Progress", "group": "started"}]


@server.tool()
def workitem(action: str, project_id: str = "", workitem_id: str = "", state: str = "",
             cursor: str = "", per_page: int = 50) -> dict:
    log("workitem", action, workitem_id=workitem_id, state=state)
    return {"results": [], "next_page_results": False}


if __name__ == "__main__":
    server.run(transport="stdio")
