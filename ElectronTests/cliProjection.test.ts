// @vitest-environment node
// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { describe, expect, it, vi } from "vitest";
import { CLIService } from "../src/main/cliService";
import {
  defaultPersistedSnapshot,
  type BaselineSnapshot,
  type HomebrewManagedItem
} from "../src/shared/domain";
import type { CLITarget } from "../src/shared/cli";
import { version } from "../src/shared/version";

function fixture(count: number) {
  const checkedAt = "2026-11-01T12:00:00.000Z";
  const items: HomebrewManagedItem[] = Array.from({ length: count }, (_, i) => ({
    id: `cask:example-${i}`,
    token: `example-${i}`,
    fullToken: `example-${i}`,
    tap: "homebrew/cask",
    name: `Example ${i}`,
    kind: "cask",
    installedVersion: version("1"),
    latestVersion: version("2"),
    isOutdated: true,
    pinned: i % 4 === 0,
    appID: `app-${i}`
  }));
  const snapshot = {
    ...defaultPersistedSnapshot(),
    apps: Array.from({ length: count }, (_, i) => ({
      id: `app-${i}`,
      displayName: `Example ${i}`,
      bundlePath: `/fixture/Example${i}.app`,
      localVersion: version("1"),
      sourceHint: "homebrew" as const
    })),
    updates: Array.from({ length: count }, (_, i) => ({
      id: `update-${i}`,
      appID: `app-${i}`,
      source: "homebrew" as const,
      supportLevel: "supported" as const,
      homebrewToken: `EXAMPLE-${i}`,
      localVersion: version("1"),
      remoteVersion: version("2"),
      checkedAt
    })),
    homebrewItems: items,
    ignoredIDs: Array.from({ length: count }, (_, i) => `app-${i}`).filter((_, i) => i % 4 === 1),
    ignoredHomebrewItemIDs: items.filter((_, i) => i % 4 === 2).map((item) => item.id),
    isRefreshing: false,
    appDiscoveryComplete: true,
    isHomebrewInstalled: true,
    isMasInstalled: false,
    isChecking: false,
    homebrewCheckStatus: "complete",
    defaultScanDirectories: [],
    lastRefreshDate: checkedAt,
    appUpdatingIDs: [],
    homebrewUpdatingItemIDs: [],
    homebrewQueuedItemIDs: [],
    homebrewUninstallingItemIDs: [],
    homebrewDiscoverInstallingItemIDs: []
  } as unknown as BaselineSnapshot;
  const service = new CLIService(
    {
      getSnapshot: () => structuredClone(snapshot),
      hasActiveUpdateOperation: () => false,
      refreshToolStatus: vi.fn(async () => undefined),
      refresh: vi.fn(async () => undefined),
      performCLIAppHandoff: vi.fn(async () => undefined),
      performHomebrewUpdate: vi.fn(async () => undefined)
    },
    "1.0.0"
  );
  return { service, snapshot };
}

async function list(service: CLIService) {
  const response = await service.handle({ schemaVersion: 1, command: "list" });
  expect(response.ok).toBe(true);
  return (response.data as { targets: CLITarget[] }).targets;
}

describe("CLI inventory projection", () => {
  it("retains every actionable and protected app/package in a large linked inventory", async () => {
    const { service } = fixture(1000);
    const targets = await list(service);
    expect(targets).toHaveLength(2000);
    expect(new Set(targets.map((target) => target.id)).size).toBe(2000);
    expect(targets.map((target) => target.id)).toEqual(
      targets.map((target) => target.id).sort((a, b) => a.localeCompare(b))
    );
    expect(targets.filter((target) => target.action === "update")).toHaveLength(250);
    expect(targets.filter((target) => target.action === "requires-user-action")).toHaveLength(250);
    expect(targets.filter((target) => target.action === "blocked")).toHaveLength(1500);
    const byID = new Map(targets.map((target) => [target.id, target]));
    for (let i = 0; i < 1000; i++) {
      expect(byID.get(`app:app-${i}`)).toMatchObject({
        installedVersion: "1",
        availableVersion: "2",
        source: "homebrew",
        pinned: i % 4 === 0,
        ignored: i % 4 === 1,
        action: i % 4 === 3 ? "requires-user-action" : "blocked"
      });
      expect(byID.get(`brew:cask:example-${i}`)).toMatchObject({
        installedVersion: "1",
        availableVersion: "2",
        linkedTargetID: `app:app-${i}`,
        pinned: i % 4 === 0,
        ignored: i % 4 === 1 || i % 4 === 2,
        action: i % 4 === 3 ? "update" : "blocked"
      });
    }
  });

  it("recomputes route protections and versions after a changed snapshot", async () => {
    const { service, snapshot } = fixture(4);
    await list(service);
    snapshot.ignoredIDs = [];
    snapshot.ignoredHomebrewItemIDs = [];
    snapshot.homebrewItems[0]!.pinned = false;
    snapshot.homebrewItems[3]!.formulaIdentityVerified = false;
    snapshot.homebrewItems[3]!.fullToken = undefined;
    snapshot.updates[0]!.remoteVersion = version("3");
    const targets = await list(service);
    expect(targets.find((target) => target.id === "app:app-0")).toMatchObject({
      pinned: false,
      availableVersion: "3",
      action: "requires-user-action"
    });
    expect(targets.filter((target) => target.ignored)).toEqual([]);
    expect(targets.find((target) => target.id === "brew:cask:example-3")).toMatchObject({
      action: "blocked",
      reason: "Installed identity is unverified."
    });
  });

  it.each(["homebrew", "sparkle"] as const)(
    "preserves the first %s update and ignores formula token collisions",
    async (source) => {
      const { service, snapshot } = fixture(1);
      snapshot.updates[0]!.source = source;
      snapshot.updates.push({ ...snapshot.updates[0]!, remoteVersion: version("9") });
      snapshot.homebrewItems.push({
        ...snapshot.homebrewItems[0]!,
        id: "cask:alias",
        pinned: false
      });
      snapshot.homebrewItems.unshift({
        ...snapshot.homebrewItems[0]!,
        id: "formula:example-0",
        kind: "formula",
        pinned: false
      });
      expect((await list(service)).find((target) => target.kind === "app")).toMatchObject({
        availableVersion: "2",
        source,
        pinned: source === "homebrew",
        action: source === "homebrew" ? "blocked" : "requires-user-action"
      });
    }
  );
});

if (process.env.BASELINE_CLI_BENCHMARK === "1") {
  it("measures repeated large list requests including snapshot cloning", async () => {
    for (const count of [500, 2000, 5000]) {
      const { service } = fixture(count);
      await list(service);
      const durations: number[] = [];
      for (let i = 0; i < 15; i++) {
        const started = performance.now();
        const targets = await list(service);
        durations.push(performance.now() - started);
        expect(targets.filter((target) => target.action === "update")).toHaveLength(count / 4);
      }
      durations.sort((a, b) => a - b);
      console.log(JSON.stringify({ count, medianMS: durations[7], p95MS: durations[14] }));
    }
  }, 30_000);
}
