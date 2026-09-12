# Live rig

Every transcript here was produced by running the real CLI (`bin/fm-plane.py`) as a
separate operating-system process, connecting over real MCP stdio framing (mcp 1.26.0)
to the stand-in Plane MCP server in `00-plane-standin-mcp-server.py`. That server keeps
one project's label vocabulary in a JSON file on disk, so the vocabulary persists across
CLI invocations exactly as a real Plane project would, and it pages label listings 2 per
page to exercise the adapter's pagination. It can also be told to refuse `label/create`
(a home whose token has no write surface), to inject a rival home's create into the race
window, and to log every MCP tool call it received.

A real Plane workspace was not used: no Plane API credentials are configured for this
adapter here, and provisioning labels into the connected production Plane workspace would
be an unrequested outward mutation.

`05-conflict-message-before-and-after-the-fix.txt` runs the same command against the same
project with two builds of the CLI - the parent commit and this branch - to show the
regression this branch's last commit fixes.
