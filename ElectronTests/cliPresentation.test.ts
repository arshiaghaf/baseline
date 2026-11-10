// @vitest-environment node
// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { expect, it } from "vitest";
import { clean, human, humanWarnings } from "../src/cli/presentation";
import { cliWantsJSON } from "../src/cli/arguments";
import type { CLIResponse, CLITarget } from "../src/shared/cli";

const target: CLITarget = {
  id: "app:/Applications/Example\u202e\u200b.app",
  kind: "app",
  name: "Example\u202e\u200b",
  installedVersion: "1",
  availableVersion: "2",
  source: "sparkle",
  ignored: false,
  pinned: false,
  action: "requires-user-action",
  checkStatus: "failed",
  checkedAt: "2026-01-01T00:00:00Z"
};
const response = (data: unknown): CLIResponse => ({
  schemaVersion: 1,
  sessionID: "session",
  ok: true,
  exitCode: 0,
  data
});

it.each(["list", "inspect", "plan"])(
  "shows %s source health independently of version availability",
  (command) => {
    const r = response({
      ...(command === "inspect" ? { target } : { targets: [target] }),
      ...(command === "plan" ? { planID: "a".repeat(64), effects: "Read-only preview." } : {}),
      appDiscoveryComplete: false,
      homebrewCheckStatus: "incomplete",
      refreshFailed: true,
      refreshing: true,
      lastRefreshAt: "2026-01-02T00:00:00Z",
      notices: ["Unreadable folder\u202e"]
    });
    expect(human(r)).toContain("CHECK\tCHECKED AT");
    expect(human(r)).toContain("failed\t2026-01-01T00:00:00Z");
    expect(human(r)).toContain("App discovery: not complete");
    expect(humanWarnings(r)).toMatch(
      /scan is running.*\n.*scan failed.*\n.*discovery is incomplete.*\n.*inventory is incomplete.*\n.*Unreadable folder\\u\{202e\}/
    );
    expect(
      JSON.parse(JSON.stringify(r)).data[command === "inspect" ? "target" : "targets"]
    ).toEqual(command === "inspect" ? target : [target]);
  }
);
it("renders terminal controls visibly only in human presentation", () => {
  const controls = "\u0000\u001b\u007f\u0085\u200b\u200e\u202e\u2066\ufeff\u2028\u2029";
  expect(clean(controls)).not.toMatch(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u);
  expect(clean("Café 日本語 👩‍💻")).toBe("Café 日本語 👩\\u{200d}💻");
  const r = response({ targets: [target] });
  expect(human(r)).toContain("Example\\u{202e}\\u{200b}");
  expect(human(r)).not.toContain("\u202e");
  expect((r.data as { targets: CLITarget[] }).targets[0]!.id).toBe(target.id);
});
it("shows doctor capabilities, exit codes and safe failure classifications", () => {
  const rendered = human(
    response({
      diagnostics: "Snapshot report\nNo private output",
      capabilities: { commands: ["check", "doctor"], maxTargets: 50 },
      exitCodes: { success: 0, failed: 1 },
      failures: [
        { entityID: "formula:example", operation: "update", reason: "permission", status: 9 }
      ]
    })
  );
  expect(rendered).toContain("commands: check, doctor");
  expect(rendered).toContain("Exit codes: 0: success, 1: failed");
  expect(rendered).toContain("Recorded failures (may predate this request)");
  expect(rendered).toContain("permission to complete. Exit status: 9");
});
it("retains operation recovery instructions in human errors and respects the option delimiter", () => {
  expect(
    human({
      ...response({
        operationID: "operation",
        outcome: "unknown-or-running",
        next: "baseline operation operation --json"
      }),
      ok: false,
      error: { code: "timeout", message: "Stopped waiting." }
    })
  ).toContain("Next: baseline operation operation --json");
  expect(cliWantsJSON(["inspect", "--", "--json"])).toBe(false);
  expect(cliWantsJSON(["--json", "inspect", "--", "--help"])).toBe(true);
});

it.each(["network", "locked", "interrupted"])(
  "does not advise repeating an installed update for %s maintenance failure",
  (reason) => {
    const text = human(
      response({
        diagnostics: "Report",
        failures: [{ entityID: "homebrew:maintenance", operation: "update", reason, status: 1 }]
      })
    );
    expect(text).toContain("do not repeat a verified installed update");
    expect(text).not.toMatch(/retry/i);
  }
);
