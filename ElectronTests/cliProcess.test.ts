// @vitest-environment node
// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { execFile, spawn } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { once } from "node:events";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { afterAll, beforeAll, expect, it } from "vitest";
import { packageCLI } from "../cliPackaging.config";
import { CLIService } from "../src/main/cliService";
import { startCLIServer } from "../src/main/cliServer";
import { cliEndpoint } from "../src/cli/endpoint";
import { defaultPersistedSnapshot, type BaselineSnapshot } from "../src/shared/domain";
import type { CLIOperation } from "../src/shared/cli";

let directory: string;
let cli: string;
beforeAll(async () => {
  directory = await mkdtemp(path.join(os.tmpdir(), "baseline-cli-process-"));
  await packageCLI(path.join(directory, "Contents/Resources/app"));
  cli = path.join(directory, "Contents/Resources/cli/cli.cjs");
});
afterAll(async () => {
  await rm(directory, { recursive: true, force: true });
});

it("keeps stdout valid JSON for non-TTY errors and local discovery", async () => {
  for (const args of [
    ["--version", "--json"],
    ["--json", "--version"],
    ["--help", "--json"],
    ["help", "update", "--json"],
    ["update", "--help", "--json"]
  ]) {
    const result = await promisify(execFile)(process.execPath, [cli, ...args]);
    expect(result.stdout.trim().split("\n")).toHaveLength(1);
    expect(JSON.parse(result.stdout)).toMatchObject({ schemaVersion: 1, ok: true });
    expect(result.stderr).toBe("");
  }
  const result = await promisify(execFile)(process.execPath, [cli, "update", "--json"]).then(
    () => {
      throw new Error("Expected usage error");
    },
    (error: { code: number; stdout: string; stderr: string }) => error
  );
  expect(result.code).toBe(2);
  expect(JSON.parse(result.stdout)).toMatchObject({ ok: false, exitCode: 2 });
  expect(result.stderr).toBe("");
});

it.each(["timeout", "SIGINT", "SIGTERM"] as const)(
  "stops a %s wait without resending or cancelling backend work",
  async (mode) => {
    const profile = path.join(directory, mode);
    const snapshot = {
      ...defaultPersistedSnapshot(),
      isRefreshing: false,
      appDiscoveryComplete: true,
      defaultScanDirectories: []
    } as unknown as BaselineSnapshot;
    let release!: () => void;
    let entered!: () => void;
    let checks = 0;
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    const started = new Promise<void>((resolve) => {
      entered = resolve;
    });
    const service = new CLIService(
      {
        getSnapshot: () => structuredClone(snapshot),
        hasActiveUpdateOperation: () => false,
        refreshToolStatus: async () => undefined,
        refresh: async () => {
          checks++;
          entered();
          await gate;
          snapshot.lastRefreshDate = new Date().toISOString();
        },
        performHomebrewUpdate: async () => undefined,
        performCLIAppHandoff: async () => undefined
      },
      "1.0.0"
    );
    const close = await startCLIServer(profile, service);
    const child = spawn(process.execPath, [cli, "check", "--json", "--timeout", "1"], {
      env: { ...process.env, BASELINE_USER_DATA_DIR: profile },
      stdio: ["ignore", "pipe", "pipe"]
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk: Buffer) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk: Buffer) => {
      stderr += chunk.toString();
    });
    const exited = once(child, "close");
    try {
      await started;
      if (mode !== "timeout") child.kill(mode);
      const [code] = await exited;
      expect(code).toBe(mode === "timeout" ? 6 : mode === "SIGINT" ? 130 : 143);
      expect(stdout.trim().split("\n")).toHaveLength(1);
      const response = JSON.parse(stdout);
      const id = response.data.operationID as string;
      expect(stderr).toContain(`Operation: ${id}`);
      expect(checks).toBe(1);
      expect(
        await service.handle({ schemaVersion: 1, command: "operation", operationID: id })
      ).toMatchObject({ data: { operation: { state: "running" } } });
      release();
      for (let n = 0; n < 100; n++) {
        const result = await service.handle({
          schemaVersion: 1,
          command: "operation",
          operationID: id
        });
        if ((result.data as { operation: CLIOperation }).operation.finishedAt) break;
        await new Promise((resolve) => setTimeout(resolve, 1));
      }
      expect(
        await service.handle({ schemaVersion: 1, command: "operation", operationID: id })
      ).toMatchObject({ data: { operation: { state: "succeeded" } } });
    } finally {
      release();
      if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
      await exited;
      await close();
      await rm(cliEndpoint(profile).directory, { recursive: true, force: true });
    }
  }
);

it.each([
  { stream: "stdout", outcome: "failed", json: true, code: 1 },
  { stream: "stdout", outcome: "updated", json: true, code: 0 },
  { stream: "stdout", outcome: "action", json: true, code: 3 },
  { stream: "stderr", outcome: "failed", json: false, code: 1 }
] as const)(
  "preserves $outcome update outcome with closed $stream",
  async ({ stream, outcome, json, code }) => {
    const profile = path.join(directory, `pipe-${stream}-${outcome}`);
    const snapshot = {
      ...defaultPersistedSnapshot(),
      isRefreshing: false,
      appDiscoveryComplete: true,
      homebrewCheckStatus: "complete",
      defaultScanDirectories: [],
      homebrewItems: [
        {
          id: "formula:example",
          token: "example",
          name: "Example",
          kind: outcome === "action" ? "cask" : "formula",
          fullToken: "example",
          tap: "homebrew/cask",
          installedVersion: { raw: "1" },
          latestVersion: { raw: "2" },
          isOutdated: true,
          formulaIdentity: {
            name: "example",
            fullName: "example",
            tap: "homebrew/core",
            oldNames: []
          }
        }
      ]
    } as unknown as BaselineSnapshot;
    let updates = 0;
    let settled = false;
    const service = new CLIService(
      {
        getSnapshot: () => structuredClone(snapshot),
        hasActiveUpdateOperation: () => false,
        refreshToolStatus: async () => undefined,
        refresh: async () => {
          snapshot.lastRefreshDate = new Date().toISOString();
        },
        performCLIAppHandoff: async () => undefined,
        performHomebrewUpdate: async () => {
          updates++;
          // Leave a window for an early stderr EPIPE; observation must continue.
          await new Promise((resolve) => setTimeout(resolve, 30));
          if (outcome === "updated") {
            snapshot.homebrewItems[0]!.installedVersion = {
              raw: "2"
            } as (typeof snapshot.homebrewItems)[0]["installedVersion"];
            snapshot.homebrewItems[0]!.isOutdated = false;
          }
          settled = true;
        }
      },
      "1.0.0"
    );
    const check = await service.handle({ schemaVersion: 1, command: "check" });
    const checkID = (check.data as { operation: CLIOperation }).operation.id;
    for (let n = 0; n < 100; n++) {
      const response = await service.handle({
        schemaVersion: 1,
        command: "operation",
        operationID: checkID
      });
      if ((response.data as { operation: CLIOperation }).operation.finishedAt) break;
      await new Promise((resolve) => setTimeout(resolve, 1));
    }
    const close = await startCLIServer(profile, service);
    const child = spawn(
      process.execPath,
      [cli, "update", "brew:formula:example", "--yes", ...(json ? ["--json"] : [])],
      {
        env: { ...process.env, BASELINE_USER_DATA_DIR: profile },
        stdio: ["ignore", "pipe", "pipe"]
      }
    );
    const exited = once(child, "close");
    child[stream].destroy();
    const other = stream === "stdout" ? child.stderr : child.stdout;
    other.resume();
    try {
      expect((await exited)[0]).toBe(code);
      expect(updates).toBe(outcome === "action" ? 0 : 1);
      if (outcome !== "action") expect(settled).toBe(true);
    } finally {
      if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
      await exited;
      await close();
      await rm(cliEndpoint(profile).directory, { recursive: true, force: true });
    }
  }
);

it("keeps human coverage warnings on stderr and exact Unicode identities in JSON", async () => {
  const profile = path.join(directory, "presentation");
  const id = "/Applications/Example\u202e\u200b.app";
  const snapshot = {
    ...defaultPersistedSnapshot(),
    isRefreshing: false,
    appDiscoveryComplete: false,
    refreshCheckFailed: true,
    refreshErrorMessage: "Unreadable folder\u202e",
    homebrewCheckStatus: "incomplete",
    defaultScanDirectories: [],
    apps: [
      {
        id,
        displayName: "Example\u202e\u200b",
        bundlePath: id,
        sourceHint: "sparkle",
        localVersion: { raw: "1" }
      }
    ],
    appProviderChecks: {
      [id]: { fingerprint: "fixture", status: "failed", checkedAt: "2026-01-01T00:00:00Z" }
    }
  } as unknown as BaselineSnapshot;
  const service = new CLIService(
    {
      getSnapshot: () => structuredClone(snapshot),
      hasActiveUpdateOperation: () => false,
      refreshToolStatus: async () => undefined,
      refresh: async () => undefined,
      performHomebrewUpdate: async () => undefined,
      performCLIAppHandoff: async () => undefined
    },
    "1.0.0"
  );
  const close = await startCLIServer(profile, service);
  const run = (args: string[]) =>
    promisify(execFile)(process.execPath, [cli, ...args], {
      env: { ...process.env, BASELINE_USER_DATA_DIR: profile }
    });
  try {
    for (const args of [["list"], ["inspect", `app:${id}`]]) {
      const result = await run(args);
      expect(result.stdout).toContain("failed\t2026-01-01T00:00:00Z");
      expect(result.stdout).toContain("Example\\u{202e}\\u{200b}");
      expect(result.stdout).not.toContain("\u202e");
      expect(result.stderr).toContain("App discovery is incomplete");
      expect(result.stderr).toContain("Unreadable folder\\u{202e}");
      const json = await run([...args, "--json"]);
      expect(json.stderr).toBe("");
      const data = JSON.parse(json.stdout).data;
      expect((data.targets?.[0] ?? data.target).id).toBe(`app:${id}`);
      expect(data.notices).toContain("Unreadable folder\u202e");
    }
  } finally {
    await close();
    await rm(cliEndpoint(profile).directory, { recursive: true, force: true });
  }
});
