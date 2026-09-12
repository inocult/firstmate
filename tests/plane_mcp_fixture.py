"""Local protocol fixture; never connects to Plane or any external service."""
from mcp.server.fastmcp import FastMCP

server = FastMCP("plane-test")
labels = [{"id": "other", "name": "other"}, {"id": "label-ready", "name": "ready-for-agent"}]
ticket = {"id": "item-1", "name": "Add export", "description_stripped": "Export all rows", "state": "ready", "labels": ["label-ready"]}


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
    return [{"id": "ready", "name": "Backlog", "group": "backlog"}]


@server.tool()
def label(action: str, project_id: str = "", name: str = "", color: str = "", description: str = "",
          cursor: str | None = None, per_page: int = 100) -> dict:
    if action == "create":
        labels.append({"id": f"label-{len(labels) + 1}", "name": name, "color": color})
        return labels[-1]
    if action != "list":
        raise ValueError("unsupported operation")
    if cursor is None:
        return {"results": labels[:1], "next_cursor": "labels-2", "next_page_results": True}
    return {"results": labels[1:], "next_page_results": False}


@server.tool()
def workitem_relation(action: str, project_id: str = "", workitem_id: str = "") -> dict:
    return {"dependencies": {"blocked_by": []}, "custom": {}}


@server.tool()
def workitem_link(action: str, project_id: str = "", workitem_id: str = "", url: str = "") -> list[dict]:
    return []


if __name__ == "__main__":
    server.run(transport="stdio")
