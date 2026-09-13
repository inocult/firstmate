"""Drive the real Plane adapter (bin/fm_plane) against an in-process tracker stub to show the
pickup guard the new filing rule relies on: a Control-filed ticket is never claimable, and no
adapter lifecycle command moves a ticket that has no claim record. The tracker is a stub, so
this is NOT a live-tracker run; the adapter code under test is the real one from the worktree."""
import asyncio, json, subprocess, sys, tempfile
from argparse import Namespace
from pathlib import Path
from unittest.mock import patch

ROOT = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(ROOT / "bin"))
from fm_plane.registry import AdapterError, Registry
from fm_plane.cli import Missions, key_for, run

NEEDS_TRIAGE, READY = "label-needs-triage", "label-ready"
STATES = [  # what the tracker project exposes; ids are the doctor's candidates
    {"id": "backlog", "name": "Backlog", "group": "backlog"},
    {"id": "todo", "name": "Todo", "group": "unstarted"},
    {"id": "blocked", "name": "Blocked", "group": "unstarted"},
    {"id": "active", "name": "In Progress", "group": "started"},
    {"id": "review", "name": "In Review", "group": "started"},
    {"id": "done", "name": "Done", "group": "completed"},
]


class StubTracker:
    def __init__(self, ticket):
        self.ticket = ticket
        self.labels = [{"id": NEEDS_TRIAGE, "name": "needs-triage"}, {"id": READY, "name": "ready-for-agent"}]
        self.tools = ["state", "label", "workitem", "workitem_link", "workitem_relation"]
        self.updates = []
    async def __aenter__(self): return self
    async def __aexit__(self, *a): return False
    async def call(self, resource, action, **args):
        if resource == "state": return STATES
        if resource == "label": return {"results": self.labels, "next_page_results": False}
        if resource == "workitem_relation": return {"dependencies": {"blocked_by": []}, "custom": {}}
        if resource == "workitem_link": return []
        if action == "retrieve": return dict(self.ticket)
        if action == "update":
            self.updates.append(args["state"]); self.ticket["state"] = args["state"]; return dict(self.ticket)
        raise AssertionError((resource, action, args))


def config(remote, pickup):
    return {"plane_url": "https://plane.example.com", "workspace_slug": "team", "project_id": "project-1",
            "repository_url": "https://github.com/example/product", "coordination_remote": remote,
            "executor": "control", "ready_label_id": READY, "pickup_state_ids": pickup,
            "states": {"implementing": "active", "review": "review", "done": "done"}, "mcp": {}}


def attempt(title, cfg, ticket, command="claim", **fields):
    tracker = StubTracker(ticket)
    registry = Registry(cfg["coordination_remote"], key_for(cfg, ticket["id"]))
    try:
        if command == "claim":
            outcome = asyncio.run(Missions(cfg, tracker, registry).claim(ticket["id"], "request-1"))
        else:
            with patch("fm_plane.cli.Plane", return_value=tracker):
                outcome = asyncio.run(run(Namespace(command=command, item=ticket["id"], **fields), cfg))
        result = "ALLOWED -> %s" % json.dumps({k: outcome.get(k) for k in ("phase", "pickup_state")} if isinstance(outcome, dict) else outcome)
    except AdapterError as exc:
        result = "REFUSED: %s" % exc
    record = registry.read()[1]
    registry.close()
    print(f"{title}\n  labels={ticket['labels']} state={ticket['state']} pickup_state_ids={cfg['pickup_state_ids']} command={command}\n"
          f"  -> {result}; tracker state now={tracker.ticket['state']}; claim record={'none' if record is None else record['phase']}\n")
    return result


with tempfile.TemporaryDirectory() as tmp:
    def fresh_remote(name):
        remote = str(Path(tmp) / f"{name}.git"); subprocess.run(["git", "init", "--bare", "-q", remote], check=True); return remote
    good = lambda name: config(fresh_remote(name), ["backlog", "todo"])  # Blocked kept out per docs/plane-missions.md
    def ticket(state, *labels): return {"id": "item-1", "name": "Commissioned work", "description_stripped": "Acceptance: it works", "state": state, "labels": list(labels)}

    print("== Doctor output for this project (what prep is told to choose from)")
    with patch("fm_plane.cli.Plane", return_value=StubTracker(ticket("backlog"))):
        doctor = asyncio.run(run(Namespace(command="doctor"), good("doctor")))
    print("  suggested_pickup_state_ids =", doctor["suggested_pickup_state_ids"], "(Blocked is suggested from the unstarted group; the guide says never configure it)\n")

    print("== Kind 1: filed for the planning team, pickup state, needs-triage only")
    r1 = attempt("planning-team ticket, no readiness label", good("k1"), ticket("backlog", NEEDS_TRIAGE))
    print("== Kind 2: commissioned, dispatch now, filed directly in implementing")
    r2 = attempt("commissioned ticket in implementing, needs-triage only", good("k2"), ticket("active", NEEDS_TRIAGE))
    r2b = attempt("adversarial: readiness label applied while in implementing", good("k2b"), ticket("active", NEEDS_TRIAGE, READY))
    print("== Kind 3: commissioned but queued, filed in Blocked")
    r3 = attempt("queued commissioned ticket in Blocked, needs-triage only", good("k3"), ticket("blocked", NEEDS_TRIAGE))
    r3b = attempt("adversarial: planning team applies readiness label while in Blocked", good("k3b"), ticket("blocked", NEEDS_TRIAGE, READY))
    print("== Adversarial: Blocked wrongly configured as a pickup state (the misconfiguration docs/plane-missions.md forbids)")
    bad = config(fresh_remote("bad"), ["backlog", "todo", "blocked"])
    r4 = attempt("Blocked in pickup_state_ids and readiness label applied", bad, ticket("blocked", NEEDS_TRIAGE, READY))
    print("== Control: the readiness label is the only thing that makes a pickup-state ticket claimable")
    r5 = attempt("planning team applies readiness label in a pickup state", good("k5"), ticket("backlog", NEEDS_TRIAGE, READY))
    print("== Binding-document claim: no adapter lifecycle command moves a ticket with no claim record")
    moves = {}
    for command, fields in [("sync", {}), ("resume", {"url": None}), ("review", {"url": None}),
                            ("complete", {"acceptance_verified": True})]:
        moves[command] = attempt(f"adapter {command} on an unclaimed Control-filed ticket", good("m-" + command),
                                 ticket("blocked", NEEDS_TRIAGE), command=command, execution="no-such-execution", **fields)

    checks = {
        "kind1 planning-team ticket refused on label": r1.startswith("REFUSED: ticket lacks the ready-for-agent label"),
        "kind2 implementing ticket refused on state": r2.startswith("REFUSED") and r2b.startswith("REFUSED: ticket is not in an eligible pickup state"),
        "kind3 Blocked ticket refused on label": r3.startswith("REFUSED: ticket lacks the ready-for-agent label"),
        "kind3 Blocked ticket refused on state even with readiness label": r3b.startswith("REFUSED: ticket is not in an eligible pickup state"),
        "misconfigured Blocked pickup state makes it claimable (why the never-configure rule exists)": r4.startswith("ALLOWED"),
        "readiness label in a pickup state is claimable (planning team's call)": r5.startswith("ALLOWED"),
        "no adapter lifecycle move without a claim record": all(v.startswith("REFUSED: execution ownership changed") for v in moves.values()),
    }
    print("== Summary")
    for name, ok in checks.items(): print(f"  [{'ok' if ok else 'FAIL'}] {name}")
    sys.exit(0 if all(checks.values()) else 1)
