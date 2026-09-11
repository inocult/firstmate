"""Local protocol fixture; never connects to Plane or any external service."""
from mcp.server.fastmcp import FastMCP

server = FastMCP("plane-test")
ticket = {"id": "item-1", "name": "Add export", "description_stripped": "Export all rows", "state": "ready"}


@server.tool()
def workitem(action: str, project_id: str = "", workitem_id: str = "", state: str = "",
             cursor: str = "", per_page: int = 50) -> dict:
    if action == "retrieve":
        return ticket
    if action == "update":
        ticket["state"] = state
        return ticket
    if action == "list":
        return {"results": [ticket], "next_cursor": "page-2", "next_page_results": True}
    raise ValueError("unsupported operation")


@server.tool()
def state(action: str, project_id: str = "") -> list[dict]:
    return [{"id": "ready", "name": "Ready for agent"}]


@server.tool()
def workitem_relation(action: str, project_id: str = "", workitem_id: str = "") -> dict:
    return {"dependencies": {"blocked_by": []}, "custom": {}}


@server.tool()
def workitem_link(action: str, project_id: str = "", workitem_id: str = "", url: str = "") -> list[dict]:
    return []


if __name__ == "__main__":
    server.run(transport="stdio")
