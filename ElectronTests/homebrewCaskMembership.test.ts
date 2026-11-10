// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, expect, it, vi } from "vitest";
import { UpdateStore } from "../src/main/updateStore";
import { SnapshotPersistence } from "../src/main/persistence";
import type { HomebrewInventoryResult } from "../src/main/homebrewInventoryClient";
import {
  defaultPersistedSnapshot,
  emptyHomebrewCaskIndex,
  emptyHomebrewFormulaIndex
} from "../src/shared/domain";
import type { AppRecord, HomebrewManagedItem, PersistedSnapshot } from "../src/shared/domain";
import { homebrewCommandToken, installedCaskEntry } from "../src/shared/homebrewIdentity";
import { canUseHomebrewAppUpdate } from "../src/main/homebrewReconciliation";
import { uninstallableHomebrewItemForApp } from "../src/renderer/helpers/sections";
import { version } from "../src/shared/version";

const app: AppRecord = {
  id: "app:desktop-tool",
  bundlePath: "/Applications/Desktop Tool.app",
  displayName: "Desktop Tool",
  localVersion: version("1"),
  sourceHint: "unknown"
};
const cask: HomebrewManagedItem = {
  id: "cask:desktop-tool",
  kind: "cask",
  token: "desktop-tool",
  fullToken: "desktop-tool",
  tap: "homebrew/cask",
  name: "Desktop Tool",
  installedVersion: version("1"),
  latestVersion: version("2"),
  isOutdated: true,
  appID: app.id
};
const formula: HomebrewManagedItem = {
  id: "formula:utility",
  kind: "formula",
  token: "utility",
  name: "Utility",
  formulaIdentity: { name: "utility", fullName: "utility", tap: "homebrew/core", oldNames: [] },
  installedVersion: version("1"),
  latestVersion: version("2"),
  isOutdated: true
};
function result(
  items = [cask, formula],
  formulaRead = true,
  caskRead = true
): HomebrewInventoryResult {
  return {
    items: structuredClone(items),
    inventoryReadSucceededByKind: { formula: formulaRead, cask: caskRead },
    outdatedDetectionSucceeded: formulaRead && caskRead,
    outdatedDetectionSucceededByKind: { formula: formulaRead, cask: caskRead }
  };
}
function deferred() {
  let resolve!: () => void;
  const promise = new Promise<void>((yes) => {
    resolve = yes;
  });
  return { promise, resolve };
}
const stores: UpdateStore[] = [];
const roots: string[] = [];
afterEach(async () => {
  for (const store of stores.splice(0)) await store.prepareToQuit();
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});
async function setup(
  fetchInventory: () => Promise<HomebrewInventoryResult> | HomebrewInventoryResult,
  persisted: Partial<PersistedSnapshot> = {},
  scanApplications = async () => [app]
) {
  const root = await mkdtemp(path.join(os.tmpdir(), "baseline-cask-membership-"));
  roots.push(root);
  const persistence = new SnapshotPersistence(root);
  const runBrewCommand = vi.fn(async (args: string[]) => ({
    success: ["--version", "update"].includes(args[0]!),
    status: ["--version", "update"].includes(args[0]!) ? 0 : 1,
    output: "Synthetic command failure"
  }));
  const options: ConstructorParameters<typeof UpdateStore>[0] = {
    persistence,
    persisted: { ...defaultPersistedSnapshot(), autoRefreshEnabled: false, ...persisted },
    runBrewCommand,
    runMasCommand: async () => ({ success: true, status: 0, output: "" }),
    openExternalURL: async () => false,
    openAppBundle: async () => undefined,
    isHomebrewCleanupUnconfirmed: () => false,
    successRefreshDelayMS: 0,
    profileStatsIntegrity: {
      verifyOrInitialize: async (stats) => ({ ...stats, integrityStatus: "verified" }),
      seal: async (stats) => stats
    },
    clients: {
      scanner: { scanApplications },
      appStore: { lookupOutcome: async () => ({ type: "completed" }) },
      sparkle: { lookupOutcome: async () => ({ type: "completed" }) },
      homebrew: {
        fetchIndex: async () => emptyHomebrewCaskIndex,
        lookupUpdate: () => ({ token: cask.token, remoteVersion: version("2") }),
        searchCasks: () => []
      },
      homebrewFormula: {
        fetchIndex: async () => emptyHomebrewFormulaIndex,
        searchFormulae: () => []
      },
      homebrewInventory: { fetchInventory: async () => fetchInventory() },
      selfUpdate: {
        lookup: async (currentVersion, checkedAt) => ({
          available: false,
          currentVersion,
          checkedAt
        })
      }
    }
  };
  const store = new UpdateStore(options);
  stores.push(store);
  return { store, options, persistence, runBrewCommand };
}

it.each(["partial", "throw"] as const)(
  "revokes cask mutations after %s membership failure and durably recovers after relaunch",
  async (failure) => {
    let phase = "healthy";
    const installed = { ...cask, appID: undefined };
    const pinned = {
      ...cask,
      id: "cask:pinned-tool",
      token: "pinned-tool",
      fullToken: "pinned-tool",
      pinned: true
    };
    const { store, options, persistence, runBrewCommand } = await setup(
      () => {
        if (phase === "failed" && failure === "throw") throw new Error("Inventory unavailable");
        if (phase === "failed") return result([formula], true, false);
        return result(
          [installed, pinned, formula],
          phase !== "failed" || failure !== "throw",
          phase !== "failed"
        );
      },
      { ignoredHomebrewItemIDs: [pinned.id] },
      async () => []
    );
    await store.refresh(true);
    expect(
      homebrewCommandToken(store.getSnapshot().homebrewItems.find((item) => item.id === cask.id)!)
    ).toBe(cask.token);
    phase = "failed";
    await store.refresh(true);
    const retained = store.getSnapshot().homebrewItems.find((item) => item.id === cask.id)!;
    expect(retained).toMatchObject({
      caskMembershipVerified: false,
      installedVersion: cask.installedVersion,
      isOutdated: false
    });
    expect(homebrewCommandToken(retained)).toBeUndefined();
    expect(installedCaskEntry(retained, emptyHomebrewCaskIndex)).toBeUndefined();
    expect(canUseHomebrewAppUpdate(app, cask.token, [retained], emptyHomebrewCaskIndex)).toBe(
      false
    );
    expect(uninstallableHomebrewItemForApp(app, store.getSnapshot())).toBeUndefined();
    await store.performHomebrewUpdate(cask.id);
    await store.performHomebrewUpdateAll([cask.id]);
    await store.uninstallHomebrewItem(cask.id);
    expect(runBrewCommand).not.toHaveBeenCalled();
    const saved = await persistence.load();
    expect(saved.homebrewItems.find((item) => item.id === cask.id)?.caskMembershipVerified).toBe(
      false
    );
    const relaunched = new UpdateStore({ ...options, persisted: saved });
    stores.push(relaunched);
    await relaunched.start(); // Availability checks do not renew installed membership.
    runBrewCommand.mockClear();
    await relaunched.refresh(true); // First actual inventory still fails.
    await relaunched.performHomebrewUpdateAll([cask.id]);
    await relaunched.uninstallHomebrewItem(cask.id);
    expect(runBrewCommand).not.toHaveBeenCalled();
    phase = "recovered";
    await relaunched.refresh(true);
    const recovered = relaunched.getSnapshot();
    expect(homebrewCommandToken(recovered.homebrewItems.find((item) => item.id === cask.id)!)).toBe(
      cask.token
    );
    expect(recovered.homebrewItems.find((item) => item.id === pinned.id)?.pinned).toBe(true);
    expect(recovered.ignoredHomebrewItemIDs).toContain(pinned.id);
    await relaunched.performHomebrewUpdate(cask.id);
    await relaunched.performHomebrewUpdateAll([cask.id]);
    await relaunched.uninstallHomebrewItem(cask.id);
    expect(
      runBrewCommand.mock.calls
        .map(([args]) => args)
        .filter((args) => ["upgrade", "uninstall"].includes(args[0]!))
    ).toEqual([
      ["upgrade", "--cask", "--greedy", cask.token],
      ["upgrade", "--cask", "--greedy", cask.token],
      ["uninstall", "--cask", cask.token]
    ]);
  }
);

it.each([
  { failure: "partial", linked: false, batch: false },
  { failure: "throw", linked: false, batch: false },
  { failure: "partial", linked: true, batch: false },
  { failure: "throw", linked: true, batch: false },
  { failure: "partial", linked: false, batch: true },
  { failure: "throw", linked: false, batch: true }
] as const)(
  "revokes new and queued cask updates before releasing $failure inventory (app linked $linked, batch $batch)",
  async ({ failure, linked, batch }) => {
    let failing = false;
    const inventory = deferred();
    const provider = deferred();
    const { store, runBrewCommand } = await setup(
      async () => {
        if (!failing) return result();
        await inventory.promise;
        if (failure === "throw") throw new Error("Inventory unavailable");
        return result([cask, formula], true, false);
      },
      { homebrewItems: [cask, formula], apps: [app] },
      async () => {
        if (failing) await provider.promise;
        return linked ? [app] : [];
      }
    );
    await store.refresh(true);
    failing = true;
    const refresh = store.refresh(true);
    let update: Promise<void> | undefined;
    try {
      if (linked) {
        expect(store.getSnapshot().updates[0]?.source).toBe("homebrew");
        expect(uninstallableHomebrewItemForApp(app, store.getSnapshot())?.id).toBe(cask.id);
      }
      update = batch
        ? store.performHomebrewUpdateAll([cask.id])
        : linked
          ? store.performAppUpdate(app.id)
          : store.performHomebrewUpdate(cask.id);
      await store.performHomebrewUpdateAll([cask.id]);
      expect(store.getSnapshot().homebrewQueuedItemIDs).toContain(cask.id);
      inventory.resolve();
      await vi.waitFor(() =>
        expect(
          homebrewCommandToken(
            store.getSnapshot().homebrewItems.find((item) => item.id === cask.id)!
          )
        ).toBeUndefined()
      );
      expect(store.getSnapshot().isRefreshing).toBe(true);
      expect(store.getSnapshot().homebrewCheckStatus).toBe("incomplete");
      await store.performHomebrewUpdate(cask.id);
      await store.performHomebrewUpdateAll([cask.id]);
      await store.uninstallHomebrewItem(cask.id);
      await store.performAppUpdate(app.id);
      expect(runBrewCommand).not.toHaveBeenCalled();
    } finally {
      inventory.resolve();
      provider.resolve();
      await Promise.allSettled([refresh, ...(update ? [update] : [])]);
    }
    expect(runBrewCommand).not.toHaveBeenCalled();
    expect(store.getSnapshot().homebrewQueuedItemIDs).toEqual([]);
    expect(store.getSnapshot().homebrewUpdatingItemIDs).toEqual([]);
  }
);

it("keeps healthy formulas usable during cask failure and restores only each proven kind", async () => {
  let phase = 0;
  const { store, runBrewCommand } = await setup(
    () => result([cask, formula], phase !== 1, phase > 2),
    { homebrewItems: [cask, formula] }
  );
  await store.refresh(true);
  expect(
    homebrewCommandToken(store.getSnapshot().homebrewItems.find((item) => item.id === formula.id)!)
  ).toBe("utility");
  await store.performHomebrewUpdate(formula.id);
  expect(runBrewCommand.mock.calls.map(([args]) => args)).toContainEqual(["upgrade", "utility"]);
  runBrewCommand.mockClear();
  phase = 1;
  await store.refresh(true);
  expect(store.getSnapshot().homebrewItems.every((item) => !homebrewCommandToken(item))).toBe(true);
  phase = 2;
  await store.refresh(true);
  expect(
    homebrewCommandToken(store.getSnapshot().homebrewItems.find((item) => item.id === formula.id)!)
  ).toBe("utility");
  expect(
    homebrewCommandToken(store.getSnapshot().homebrewItems.find((item) => item.id === cask.id)!)
  ).toBeUndefined();
  phase = 3;
  await store.refresh(true);
  expect(
    homebrewCommandToken(store.getSnapshot().homebrewItems.find((item) => item.id === cask.id)!)
  ).toBe(cask.token);
});

it.each(["same-tap", "changed-tap", "explicit-unpin", "historical-name"] as const)(
  "preserves pin evidence across cask membership failure without transferring it on %s recovery",
  async (recovery) => {
    let phase = 0;
    const previous = { ...cask, pinned: true };
    const fresh = {
      ...cask,
      ...(recovery === "changed-tap"
        ? { tap: "example/tools", fullToken: `example/tools/${cask.token}` }
        : {}),
      ...(recovery === "explicit-unpin" ? { pinned: false } : {}),
      ...(recovery === "historical-name"
        ? {
            fullToken: "old-desktop-tool",
            caskMetadata: {
              token: cask.token,
              fullToken: "old-desktop-tool",
              tap: "homebrew/cask",
              name: cask.name,
              version: version("2"),
              bundleIdentifiers: [],
              presentation: "cask" as const,
              appBundleNames: []
            }
          }
        : {})
    };
    const { store, options, persistence } = await setup(() =>
      result(phase === 0 ? [previous] : [fresh], true, phase !== 1)
    );
    await store.refresh(true);
    phase = 1;
    await store.refresh(true);
    const retained = store.getSnapshot().homebrewItems[0]!;
    expect(retained.pinned).toBe(true);
    expect(homebrewCommandToken(retained)).toBeUndefined();
    const relaunched = new UpdateStore({ ...options, persisted: await persistence.load() });
    stores.push(relaunched);
    phase = 2;
    await relaunched.refresh(true);
    const recovered = relaunched.getSnapshot().homebrewItems[0]!;
    expect(recovered.pinned).toBe(
      recovery === "explicit-unpin" ? false : recovery === "changed-tap" ? undefined : true
    );
    expect(homebrewCommandToken(recovered)).toBe(
      recovery === "changed-tap" || recovery === "historical-name"
        ? `${recovered.tap}/${cask.token}`
        : cask.token
    );
  }
);

it.each(["removed", "unverified"] as const)(
  "does not restore stale cask authority after a successful but %s recovery",
  async (recovery) => {
    let phase = 0;
    const { store, runBrewCommand } = await setup(() =>
      phase === 0
        ? result([cask])
        : phase === 1
          ? result([], true, false)
          : result(
              recovery === "removed" ? [] : [{ ...cask, fullToken: undefined, tap: undefined }]
            )
    );
    await store.refresh(true);
    phase = 1;
    await store.refresh(true);
    phase = 2;
    await store.refresh(true);
    if (recovery === "removed") expect(store.getSnapshot().homebrewItems).toEqual([]);
    else expect(homebrewCommandToken(store.getSnapshot().homebrewItems[0]!)).toBeUndefined();
    await store.performHomebrewUpdate(cask.id);
    await store.performHomebrewUpdateAll([cask.id]);
    await store.uninstallHomebrewItem(cask.id);
    expect(runBrewCommand).not.toHaveBeenCalled();
  }
);
