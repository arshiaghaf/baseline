// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { afterEach, expect, it, vi } from "vitest";
import { reconcileScannedApps, testingExports } from "../src/main/scanReconciliation";
import type { AppRecord } from "../src/shared/domain";
import { version } from "../src/shared/version";

afterEach(() => vi.restoreAllMocks());
const app = (bundlePath: string): AppRecord => ({
  id: bundlePath,
  bundlePath,
  displayName: "Utility",
  localVersion: version("1"),
  sourceHint: "unknown"
});

it.each(["caller", "deadline"] as const)(
  "bounds prior identity resolution on %s cancellation and observes late rejection",
  async (cause) => {
    const caller = new AbortController();
    const deadline = new AbortController();
    vi.spyOn(AbortSignal, "timeout").mockReturnValue(deadline.signal);
    let reject!: (error: Error) => void;
    const blocked = new Promise<string>((_, fail) => {
      reject = fail;
    });
    const resolve = vi.spyOn(testingExports.identityRuntime, "realpath").mockReturnValue(blocked);
    const old = [app("/old/Utility.app"), app("/another/Utility.app")];
    const fresh = app("/alias/Utility.app");
    const task = reconcileScannedApps(
      [fresh],
      old,
      old,
      new Map([[fresh.bundlePath, "/canonical/Utility.app"]]),
      [old[0]!.id],
      caller.signal
    );
    let result: Awaited<typeof task> | undefined;
    let failure: unknown;
    const observed = task.then(
      (value) => {
        result = value;
      },
      (error: unknown) => {
        failure = error;
      }
    );
    const reason = new Error("cancelled");
    try {
      (cause === "caller" ? caller : deadline).abort(reason);
      await vi.waitFor(() => expect(result !== undefined || failure !== undefined).toBe(true), {
        timeout: 200
      });
      if (cause === "caller") expect(failure).toBe(reason);
      else expect(result).toEqual({ scannedApps: [fresh], retainedApps: old });
      expect(resolve).toHaveBeenCalledTimes(1);
    } finally {
      reject(new Error("late IO failure"));
      await blocked.catch(() => {});
      await observed;
    }
  }
);

it.each([false, true])(
  "keeps the original historical ID when its alias path is reused (retained: %s)",
  async (unavailable) => {
    const alias = "/fixture/Alias.app";
    const canonical = "/fixture/Canonical.app";
    const controller = new AbortController();
    const collapsed = await reconcileScannedApps(
      [app(canonical)],
      [],
      [app(alias)],
      new Map([
        [alias, canonical],
        [canonical, canonical]
      ]),
      [alias],
      controller.signal
    );
    const original = collapsed.scannedApps[0]!;
    expect(original).toMatchObject({ id: alias, bundlePath: canonical });
    vi.spyOn(testingExports.identityRuntime, "realpath").mockRejectedValue(new Error("offline"));
    let previous = [original];
    let newID: string | undefined;
    for (const reverse of [true, false, true]) {
      const scanned = unavailable ? [app(alias)] : [app(canonical), app(alias)];
      if (reverse) scanned.reverse();
      const result = await reconcileScannedApps(
        scanned,
        unavailable ? [original] : [],
        previous,
        new Map(scanned.map((item) => [item.bundlePath, item.bundlePath])),
        [alias],
        controller.signal
      );
      previous = [...result.scannedApps, ...result.retainedApps];
      expect(previous).toHaveLength(2);
      expect(new Set(previous.map((item) => item.id)).size).toBe(2);
      expect(previous.find((item) => item.bundlePath === canonical)?.id).toBe(alias);
      const replacementID = previous.find((item) => item.bundlePath === alias)!.id;
      expect(replacementID).not.toBe(alias);
      if (newID) expect(replacementID).toBe(newID);
      newID = replacementID;
    }
    const recovered = await reconcileScannedApps(
      [app(alias), app(canonical)],
      [],
      previous,
      new Map([
        [alias, alias],
        [canonical, canonical]
      ]),
      [alias],
      controller.signal
    );
    expect(recovered.scannedApps.find((item) => item.bundlePath === canonical)?.id).toBe(alias);
    expect(recovered.scannedApps.find((item) => item.bundlePath === alias)?.id).toBe(newID);
  }
);

it("repairs an already-colliding snapshot without assigning the original ignore identity to the replacement", async () => {
  const alias = app("/fixture/Alias.app");
  const original = { ...app("/fixture/Canonical.app"), id: alias.id };
  const result = await reconcileScannedApps(
    [alias, app(original.bundlePath)],
    [],
    [alias, original],
    new Map([
      [alias.bundlePath, alias.bundlePath],
      [original.bundlePath, original.bundlePath]
    ]),
    [original.id],
    new AbortController().signal
  );
  expect(result.scannedApps.find((item) => item.bundlePath === original.bundlePath)?.id).toBe(
    original.id
  );
  expect(result.scannedApps.find((item) => item.bundlePath === alias.bundlePath)?.id).not.toBe(
    original.id
  );
});

it("does not give a new installation an orphaned ignored ID", async () => {
  const fresh = app("/fixture/Utility.app");
  const result = await reconcileScannedApps(
    [fresh],
    [],
    [],
    new Map(),
    [fresh.id],
    new AbortController().signal
  );
  expect(result.scannedApps[0]!.id).not.toBe(fresh.id);
});
