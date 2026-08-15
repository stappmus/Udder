import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("../Model.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*/u, "");
const model = { console, Date, JSON, Object, Array, Number, String, Math, isFinite };
vm.createContext(model);
vm.runInContext(source, model, { filename: "Model.js" });

const snapshot = {
  id: "test",
  result: {
    type: "session_snapshot",
    snapshot: {
      version: "0.8.0",
      protocol: 20,
      workspaces: [
        { workspace_id: "w1", number: 1, label: "API" },
        { workspace_id: "w2", number: 2, label: "Docs" }
      ],
      tabs: [
        { tab_id: "w1:t1", number: 1 },
        { tab_id: "w2:t1", number: 1 }
      ],
      panes: [
        { pane_id: "w1:p1" },
        { pane_id: "w2:p1" }
      ],
      agents: [
        {
          pane_id: "w1:p1", workspace_id: "w1", tab_id: "w1:t1",
          agent: "codex", agent_status: "working", cwd: "/work/API"
        },
        {
          pane_id: "w2:p1", workspace_id: "w2", tab_id: "w2:t1",
          agent: "claude", agent_status: "done", cwd: "/work/Docs"
        }
      ]
    }
  }
};

const parsed = model.parseSnapshot(JSON.stringify(snapshot));
assert.equal(parsed.ok, true);
assert.equal(parsed.agents.length, 2);
assert.equal(parsed.agents[0].paneId, "w2:p1", "attention states sort first");
assert.equal(parsed.agents[0].workspaceLabel, "Docs");
assert.deepEqual(Array.from(parsed.paneIds), ["w1:p1", "w2:p1"]);
assert.deepEqual(
  JSON.parse(JSON.stringify(model.countAgents(parsed.agents))),
  { total: 2, working: 1, blocked: 0, done: 1, idle: 0, unknown: 0 }
);

const focusRequest = model.paneFocusRequest("w7:p1", "test-focus");
assert.deepEqual(JSON.parse(JSON.stringify(focusRequest)), {
  id: "test-focus",
  method: "pane.focus",
  params: { pane_id: "w7:p1" }
});
const focusResponse = model.parsePaneFocusResponse(JSON.stringify({
  id: "test-focus",
  result: { type: "pane_info", pane: { pane_id: "w7:p1", focused: true } }
}), "test-focus");
assert.equal(focusResponse.handled, true);
assert.equal(focusResponse.ok, true);
assert.equal(focusResponse.paneId, "w7:p1");
assert.equal(model.parsePaneFocusResponse(JSON.stringify({
  id: "another-request",
  result: { pane: { pane_id: "w1:p1" } }
}), "test-focus").handled, false);

const event = model.parseEvent(JSON.stringify({
  event: "pane_agent_status_changed",
  data: {
    type: "pane_agent_status_changed",
    pane_id: "w1:p1",
    workspace_id: "w1",
    agent: "codex",
    agent_status: "done"
  }
}), JSON.stringify({
  workspace_label: "API",
  focused_pane_cwd: "/work/API"
}));
assert.equal(event.ok, true);
assert.equal(event.kind, "status");
assert.equal(event.status, "done");
assert.equal(event.workspaceLabel, "API");

const released = model.parseEvent(JSON.stringify({
  event: "pane_agent_detected",
  data: {
    type: "pane_agent_detected",
    pane_id: "w2:p1",
    workspace_id: "w2",
    agent: "claude",
    released: true,
    final_status: "done"
  }
}), "{}");
assert.equal(released.ok, true);
assert.equal(released.kind, "detected");
assert.equal(released.released, true);
assert.equal(released.finalStatus, "done");

const pending = model.parsePending(JSON.stringify({
  schemaVersion: 1,
  pending: {
    "w1:p1": {
      workspaceLabel: "API", agent: "codex", released: true,
      finalStatus: "done", createdAt: 42
    }
  }
}));
assert.equal(pending.ok, true);
assert.equal(pending.pending["w1:p1"].agentLabel, "Codex");
assert.equal(pending.pending["w1:p1"].released, true);
assert.equal(pending.pending["w1:p1"].finalStatus, "done");
assert.equal(model.parsePending("not json").ok, false);

console.log("model tests passed");
