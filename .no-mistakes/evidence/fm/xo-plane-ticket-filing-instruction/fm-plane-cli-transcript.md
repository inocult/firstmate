# fm-plane adapter CLI transcript against a seeded copy of tests/plane_mcp_fixture.py
# Configured pickup_state_ids: ["ready"] (Backlog); Blocked deliberately not configured, per docs/plane-missions.md.

## doctor: Blocked is listed as a project state but not among suggested pickup states
$ bin/fm-plane.py --config plane.json doctor
{
  "mcp_tools": [
    "label",
    "state",
    "workitem",
    "workitem_link",
    "workitem_relation"
  ],
  "project": "project-1",
  "states": [
    {
      "id": "ready",
      "name": "Backlog",
      "group": "backlog"
    },
    {
      "id": "active",
      "name": "In Progress",
      "group": "started"
    },
    {
      "id": "blocked",
      "name": "Blocked",
      "group": "started"
    }
  ],
  "labels": [
    {
      "id": "other",
      "name": "other"
    },
    {
      "id": "label-ready",
      "name": "ready-for-agent"
    },
    {
      "id": "label-triage",
      "name": "needs-triage"
    }
  ],
  "suggested_ready_label_id": "label-ready",
  "suggested_pickup_state_ids": [
    "ready"
  ],
  "executor": "control",
  "note": "MCP connected; no ticket or claim changed"
}
exit=0

## list: the filed tickets are visible in the shared backlog
$ bin/fm-plane.py --config plane.json list
{
  "results": [
    {
      "id": "item-1",
      "name": "Add export",
      "description_stripped": "Export all rows",
      "state": "ready",
      "labels": [
        "label-ready"
      ]
    },
    {
      "id": "planning-team",
      "sequence_id": 2,
      "name": "Filed for the planning team",
      "description_stripped": "Acceptance: assessed",
      "state": "ready",
      "labels": [
        "label-triage"
      ]
    },
    {
      "id": "commissioned-now",
      "sequence_id": 3,
      "name": "Commissioned and dispatched now",
      "description_stripped": "Acceptance: lands",
      "state": "active",
      "labels": [
        "label-triage",
        "label-ready"
      ]
    },
    {
      "id": "commissioned-queued",
      "sequence_id": 4,
      "name": "Commissioned but queued",
      "description_stripped": "Acceptance: lands after gate",
      "state": "blocked",
      "labels": [
        "label-triage",
        "label-ready"
      ]
    }
  ],
  "next_cursor": "page-2",
  "next_page_results": true
}
exit=0

## claim planning-team ticket (Backlog, needs-triage only): refused until the planning team applies ready-for-agent
$ bin/fm-plane.py --config plane.json claim --item planning-team --request-id r-planning
{"error": "ticket lacks the ready-for-agent label"}
exit=1

## claim commissioned ticket filed in implementing, even with ready-for-agent: refused
$ bin/fm-plane.py --config plane.json claim --item commissioned-now --request-id r-now
{"error": "ticket is not in an eligible pickup state"}
exit=1

## claim queued commissioned ticket in Blocked, even with ready-for-agent: refused
$ bin/fm-plane.py --config plane.json claim --item commissioned-queued --request-id r-queued
{"error": "ticket is not in an eligible pickup state"}
exit=1

## sync on a Control-filed ticket with no claim record: refused
$ bin/fm-plane.py --config plane.json sync --item commissioned-queued --execution 00000000-0000-0000-0000-000000000000
{"error": "execution ownership changed or belongs to another operative"}
exit=1

## resume on a Control-filed ticket with no claim record: refused
$ bin/fm-plane.py --config plane.json resume --item commissioned-queued --execution 00000000-0000-0000-0000-000000000000
{"error": "execution ownership changed or belongs to another operative"}
exit=1

## complete on a Control-filed ticket with no claim record: refused
$ bin/fm-plane.py --config plane.json complete --item commissioned-queued --execution 00000000-0000-0000-0000-000000000000 --acceptance-verified
{"error": "execution ownership changed or belongs to another operative"}
exit=1

## ADVERSARIAL: same Blocked ticket with Blocked wrongly configured in pickup_state_ids: claimed (the failure the never-configure rule guards against)
$ bin/fm-plane.py --config plane-misconfigured.json claim --item commissioned-queued --request-id r-wrong
{
  "execution": "d2a254e7-3ec2-4144-ad10-6ec0311cdd67",
  "executor": "control",
  "item": "commissioned-queued",
  "past_requests": [],
  "phase": "implementing",
  "pickup_state": "blocked",
  "pr": null,
  "project": "project-1",
  "repository_url": "https://github.com/example/product",
  "request_id": "r-wrong",
  "schema": 1,
  "task": null,
  "updated_at": 1789266070
}
exit=0
