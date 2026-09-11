"""Official MCP SDK transport, with modern and advertised legacy Plane tools."""

import asyncio
import json
import os
from contextlib import AsyncExitStack
from .registry import AdapterError


class Plane:
    def __init__(self, config):
        self.config = config
        self.stack = AsyncExitStack()

    async def __aenter__(self):
        try:
            from mcp import ClientSession, StdioServerParameters
            from mcp.client.stdio import stdio_client
            from mcp.client.streamable_http import streamablehttp_client
        except ImportError as exc:
            raise AdapterError("install the optional requirements-plane.txt in the adapter Python environment") from exc
        try:
            if "command" in self.config:
                env = dict(os.environ)
                for key, name in self.config.get("env_from", {}).items():
                    if not os.environ.get(name):
                        raise AdapterError(f"missing environment variable: {name}")
                    env[key] = os.environ[name]
                params = StdioServerParameters(command=self.config["command"],
                                               args=self.config.get("args", []), env=env)
                # Server stderr may include API responses; do not relay it to chat/logs.
                self.errlog = self.stack.enter_context(open(os.devnull, "w"))
                read, write = await self.stack.enter_async_context(stdio_client(params, errlog=self.errlog))
            else:
                headers = {}
                for key, name in self.config.get("headers_from", {}).items():
                    if not os.environ.get(name):
                        raise AdapterError(f"missing environment variable: {name}")
                    headers[key] = os.environ[name]
                read, write, _ = await self.stack.enter_async_context(
                    streamablehttp_client(self.config["url"], headers=headers))
            self.session = await self.stack.enter_async_context(ClientSession(read, write))
            await self.session.initialize()
            self.tools = set()
            cursor = None
            while True:
                page = await self.session.list_tools(cursor=cursor)
                self.tools.update(tool.name for tool in page.tools)
                cursor = page.nextCursor
                if not cursor:
                    break
            return self
        except BaseException:
            await self.stack.aclose()
            raise

    async def __aexit__(self, *exc):
        return await self.stack.__aexit__(*exc)

    async def call(self, resource, action, **arguments):
        legacy = {
            ("state", "list"): "list_states",
            ("label", "list"): "list_labels",
            ("workitem", "list"): "list_work_items",
            ("workitem", "retrieve"): "retrieve_work_item",
            ("workitem", "update"): "update_work_item",
            ("workitem_link", "list"): "list_work_item_links",
            ("workitem_link", "create"): "create_work_item_link",
            ("workitem_relation", "list"): "list_work_item_relations",
        }
        if resource in self.tools:
            name, args = resource, dict(arguments, action=action)
        else:
            name = legacy.get((resource, action))
            if name not in self.tools:
                raise AdapterError(f"Plane MCP lacks {resource}/{action}; inspect the connected schema")
            args = dict(arguments)
            if "workitem_id" in args:
                args["work_item_id"] = args.pop("workitem_id")
        result = await asyncio.wait_for(self.session.call_tool(name, args), timeout=40)
        if result.isError:
            raise AdapterError(f"Plane MCP rejected {resource}/{action}; claim retained")
        payload = result.structuredContent
        if payload is None:
            texts = [part.text for part in result.content if getattr(part, "type", "") == "text"]
            try:
                payload = json.loads("\n".join(texts))
            except ValueError as exc:
                raise AdapterError("Plane MCP returned non-JSON data; inspect server compatibility") from exc
        # MCP SDK wraps non-object structured outputs in a result key.
        if isinstance(payload, dict) and set(payload) == {"result"}:
            payload = payload["result"]
        if isinstance(payload, dict) and (payload.get("error") or payload.get("success") is False):
            raise AdapterError(f"Plane returned an application error for {resource}/{action}")
        return payload


def rows(payload):
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict) and isinstance(payload.get("results"), list):
        return payload["results"]
    raise AdapterError("unrecognized Plane list response; refusing to assume it is empty")
