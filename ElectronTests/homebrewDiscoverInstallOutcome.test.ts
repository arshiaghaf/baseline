// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { describe, expect, it, vi } from "vitest";
import {
  defaultPersistedSnapshot,
  type HomebrewCaskDiscoveryItem,
  type HomebrewManagedItemKind
} from "../src/shared/domain";
import { version } from "../src/shared/version";
import type { CommandResult } from "../src/main/commandRunner";
import {
  HomebrewOperationsService,
  type HomebrewOperationsState
} from "../src/main/homebrewOperationsService";
import { HomebrewWorkLock } from "../src/main/homebrewWorkLock";

function discoveryItem(kind: HomebrewManagedItemKind): HomebrewCaskDiscoveryItem {
  return {
    id: `${kind}:example`,
    kind,
    token: "example",
    displayName: "Example",
    version: version("2.0")
  };
}

function harness(run: (args: string[], onLine?: (line: string) => void) => Promise<CommandResult>) {
  let state: HomebrewOperationsState = {
    ...defaultPersistedSnapshot(),
    homebrewUpdatingItemIDs: [],
    homebrewQueuedItemIDs: [],
    homebrewBatchFailedItemIDs: [],
    homebrewBatchProgressByItemID: {},
    homebrewUpdatedPendingRefreshItemIDs: [],
    homebrewDiscoverInstallingItemIDs: [],
    homebrewDiscoverFailedItemIDs: [],
    homebrewDiscoverProgressByItemID: {},
    homebrewDiscoverInstalledPendingRefreshItemIDs: [],
    homebrewUninstallingItemIDs: [],
    isRunningHomebrewMaintenance: false,
    isHomebrewInstalled: true
  };
  const snapshots: HomebrewOperationsState[] = [];
  const runCommand = vi.fn(run);
  const refresh = vi.fn(async () => undefined);
  const stats = vi.fn(async () => undefined);
  const failure = vi.fn(async () => undefined);
  const clearFailure = vi.fn();
  const lock = new HomebrewWorkLock<never>({
    hasOtherMutation: () => state.homebrewDiscoverInstallingItemIDs.length > 0,
    onLockStateChange: () => undefined,
    onCommandReleased: () => undefined
  });
  const service = new HomebrewOperationsService({
    getState: () => state,
    patch: (patch) => {
      state = { ...state, ...patch };
      snapshots.push(state);
    },
    lock,
    runBrewCommand: runCommand,
    emitHomebrewCommand: () => undefined,
    refresh: async (allowInventory) => {
      expect(allowInventory).toBe(true);
      expect(lock.activeCommandCount).toBe(1);
      await refresh();
    },
    recordProfileStatsEvents: stats,
    clearOperationFailure: clearFailure,
    recordOperationFailure: failure,
    recordOperationFailures: async () => undefined,
    hasCheckedHomebrewAvailability: () => true,
    markHomebrewAvailabilityChecked: () => undefined,
    requiresInventory: () => false,
    successRefreshDelayMS: 0
  });
  return {
    service,
    lock,
    runCommand,
    refresh,
    stats,
    failure,
    clearFailure,
    snapshots,
    get state() {
      return state;
    }
  };
}

function expectIdle(h: ReturnType<typeof harness>) {
  expect(h.state.homebrewDiscoverInstallingItemIDs).toEqual([]);
  expect(h.state.homebrewOperation).toBeUndefined();
  expect(h.lock.activeCommandCount).toBe(0);
}

describe.each(["formula", "cask"] as const)("Discover %s install outcomes", (kind) => {
  it.each(["streamed", "returned"] as const)(
    "does not count an already-installed %s result, including repeated attempts",
    async (delivery) => {
      const output = "Warning: example 2.0 is already installed and up-to-date.";
      const h = harness(async (_args, onLine) => {
        if (delivery === "streamed") onLine?.(output);
        return { success: true, status: 0, output: delivery === "returned" ? output : "" };
      });
      try {
        // Keep stale discovery results to exercise a second click before the
        // catalog has reconciled an externally installed package.
        for (let attempt = 0; attempt < 2; attempt++) {
          await h.service.installHomebrewItem(discoveryItem(kind));
          expectIdle(h);
          expect(h.state.homebrewDiscoverFailedItemIDs).toEqual([]);
          expect(h.state.homebrewDiscoverProgressByItemID).toEqual({});
        }
        expect(h.stats).not.toHaveBeenCalled();
        expect(h.failure).not.toHaveBeenCalled();
        expect(h.refresh).toHaveBeenCalledTimes(2);
        expect(
          h.snapshots.every((s) => !s.homebrewDiscoverInstalledPendingRefreshItemIDs.length)
        ).toBe(true);
        expect(h.runCommand.mock.calls.map(([args]) => args)).toEqual([
          kind === "cask" ? ["install", "--cask", "example"] : ["install", "example"],
          kind === "cask" ? ["install", "--cask", "example"] : ["install", "example"]
        ]);
      } finally {
        h.service.dispose();
      }
    }
  );

  it.each(["", "🍺 example was successfully installed!"])(
    "preserves genuine successful installation accounting with output %j",
    async (output) => {
      const h = harness(async (_args, onLine) => {
        onLine?.(output);
        return { success: true, status: 0, output };
      });
      try {
        await h.service.installHomebrewItem(discoveryItem(kind));
        expect(h.stats).toHaveBeenCalledExactlyOnceWith([
          expect.objectContaining({ type: "homebrewInstall", targetID: `${kind}:example` })
        ]);
        expect(h.state.homebrewDiscoverInstalledPendingRefreshItemIDs).toEqual([`${kind}:example`]);
        expect(h.refresh).toHaveBeenCalledOnce();
        expectIdle(h);
      } finally {
        h.service.dispose();
      }
    }
  );

  it("does not mistake dependency completion for installation of an unchanged target", async () => {
    const h = harness(async (_args, onLine) => {
      onLine?.("Warning: example 2.0 already installed");
      return { success: true, status: 0, output: "🍺 dependency was successfully installed!" };
    });
    try {
      await h.service.installHomebrewItem(discoveryItem(kind));
      expect(h.stats).not.toHaveBeenCalled();
      expect(h.state.homebrewDiscoverInstalledPendingRefreshItemIDs).toEqual([]);
      expect(h.refresh).toHaveBeenCalledOnce();
      expectIdle(h);
    } finally {
      h.service.dispose();
    }
  });

  it.each([true, false])(
    "ignores other-kind completion for the same token (completion streamed: %s)",
    async (completionStreamed) => {
      const completed =
        kind === "cask"
          ? "🍺 /opt/homebrew/Cellar/example/2.0: 5 files, 1KB"
          : "🍺 Cask example was successfully installed!";
      const unchanged = `Warning: ${kind} example 2.0 already installed`;
      const h = harness(async (_args, onLine) => {
        onLine?.(completionStreamed ? completed : unchanged);
        return { success: true, status: 0, output: completionStreamed ? unchanged : completed };
      });
      try {
        await h.service.installHomebrewItem(discoveryItem(kind));
        expect(h.stats).not.toHaveBeenCalled();
        expect(h.state.homebrewDiscoverInstalledPendingRefreshItemIDs).toEqual([]);
        expect(h.state.homebrewDiscoverProgressByItemID).toEqual({});
        expect(h.refresh).toHaveBeenCalledOnce();
        expectIdle(h);
      } finally {
        h.service.dispose();
      }
    }
  );

  it("does not mistake another kind's unchanged notice for a target no-op", async () => {
    const otherKind = kind === "cask" ? "formula" : "cask";
    const h = harness(async (_args, onLine) => {
      onLine?.(`Warning: ${otherKind} example 2.0 already installed`);
      return { success: true, status: 0, output: "" };
    });
    try {
      await h.service.installHomebrewItem(discoveryItem(kind));
      expect(h.stats).toHaveBeenCalledOnce();
      expect(h.state.homebrewDiscoverInstalledPendingRefreshItemIDs).toEqual([`${kind}:example`]);
      expect(h.refresh).toHaveBeenCalledOnce();
      expectIdle(h);
    } finally {
      h.service.dispose();
    }
  });

  it("does not let an ambiguous dependency summary override an explicit target no-op", async () => {
    const h = harness(async (_args, onLine) => {
      onLine?.("Warning: example 2.0 already installed");
      return {
        success: true,
        status: 0,
        output: "🍺 Finished installing dependency (required by example)"
      };
    });
    try {
      await h.service.installHomebrewItem(discoveryItem(kind));
      expect(h.stats).not.toHaveBeenCalled();
      expect(h.state.homebrewDiscoverInstalledPendingRefreshItemIDs).toEqual([]);
      expect(h.refresh).toHaveBeenCalledOnce();
      expectIdle(h);
    } finally {
      h.service.dispose();
    }
  });

  it.each([true, false])(
    "retains target completion evidence alongside an unchanged notice (completion streamed: %s)",
    async (completionStreamed) => {
      const completed =
        kind === "cask"
          ? "🍺 example was successfully installed!"
          : "🍺 /opt/homebrew/Cellar/example/2.0: 5 files, 1KB";
      const unchanged = "Warning: example 2.0 already installed";
      const h = harness(async (_args, onLine) => {
        onLine?.(completionStreamed ? completed : unchanged);
        return { success: true, status: 0, output: completionStreamed ? unchanged : completed };
      });
      try {
        await h.service.installHomebrewItem(discoveryItem(kind));
        expect(h.stats).toHaveBeenCalledOnce();
        expect(h.state.homebrewDiscoverInstalledPendingRefreshItemIDs).toEqual([`${kind}:example`]);
        expect(h.refresh).toHaveBeenCalledOnce();
        expectIdle(h);
      } finally {
        h.service.dispose();
      }
    }
  );

  it("reconciles a failure and a no-op retry without leaking completion evidence", async () => {
    let attempt = 0;
    const h = harness(async (_args, onLine) => {
      attempt++;
      if (attempt === 1) {
        onLine?.("🍺 example was successfully installed!");
        return { success: false, status: 1, output: "Error: post-install failed" };
      }
      if (attempt === 2) {
        return { success: true, status: 0, output: "Warning: example 2.0 already installed" };
      }
      return { success: true, status: 0, output: "🍺 example was successfully installed!" };
    });
    try {
      const item = discoveryItem(kind);
      await h.service.installHomebrewItem(item);
      expect(h.state.homebrewDiscoverFailedItemIDs).toEqual([item.id]);
      expect(h.stats).not.toHaveBeenCalled();
      expectIdle(h);
      await h.service.installHomebrewItem(item);
      expect(h.state.homebrewDiscoverFailedItemIDs).toEqual([]);
      expect(h.state.homebrewDiscoverInstalledPendingRefreshItemIDs).toEqual([]);
      expect(h.state.homebrewDiscoverProgressByItemID).toEqual({});
      expect(h.state.refreshErrorMessage).toBeUndefined();
      expect(h.stats).not.toHaveBeenCalled();
      expectIdle(h);
      await h.service.installHomebrewItem(item);
      expect(h.stats).toHaveBeenCalledOnce();
      expect(h.failure).toHaveBeenCalledOnce();
      expect(h.clearFailure).toHaveBeenCalledTimes(3);
      expect(h.refresh).toHaveBeenCalledTimes(3);
      expectIdle(h);
    } finally {
      h.service.dispose();
    }
  });

  it("releases the reservation when no-op inventory reconciliation fails", async () => {
    const h = harness(async () => ({
      success: true,
      status: 0,
      output: "Warning: example 2.0 already installed"
    }));
    h.refresh.mockRejectedValue(new Error("inventory unavailable"));
    try {
      await expect(h.service.installHomebrewItem(discoveryItem(kind))).rejects.toThrow(
        "inventory unavailable"
      );
      expect(h.stats).not.toHaveBeenCalled();
      expect(h.state.homebrewDiscoverInstalledPendingRefreshItemIDs).toEqual([]);
      expect(h.state.homebrewDiscoverProgressByItemID).toEqual({});
      expectIdle(h);
    } finally {
      h.service.dispose();
    }
  });
});
