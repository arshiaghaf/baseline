// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { randomUUID } from "node:crypto";
import { realpath } from "node:fs/promises";
import type { AppRecord } from "../shared/domain";
import { cancellableRead, readSignal } from "./readCancellation";

const identityRuntime = { realpath };

export function ambiguousAppIDs(apps: readonly AppRecord[]): Set<string> {
  const seen = new Set<string>();
  const ambiguous = new Set<string>();
  for (const app of apps) {
    if (seen.has(app.id)) ambiguous.add(app.id);
    seen.add(app.id);
  }
  return ambiguous;
}

// Resolve only uncertain prior paths. One shared budget bounds the whole extra
// reconciliation pass; unavailable identity evidence must never remove a record.
export async function reconcileScannedApps(
  scanned: AppRecord[],
  retained: AppRecord[],
  previous: AppRecord[],
  canonicalPaths: ReadonlyMap<string, string>,
  ignoredIDs: readonly string[],
  signal: AbortSignal
): Promise<{ scannedApps: AppRecord[]; retainedApps: AppRecord[] }> {
  const byCanonical = new Map<string, AppRecord[]>();
  const addIdentity = (app: AppRecord, canonical: string) => {
    const group = byCanonical.get(canonical) ?? [];
    group.push(app);
    byCanonical.set(canonical, group);
  };
  // The scanner also reports proven aliases skipped by its own deduplication.
  // Their roots may be healthy, so they need not appear among retained records.
  for (const app of previous) {
    const canonical = canonicalPaths.get(app.bundlePath);
    if (canonical) addIdentity(app, canonical);
  }
  const deadline = retained.length && canonicalPaths.size ? readSignal(signal) : undefined;
  for (const app of retained) {
    signal.throwIfAborted();
    if (canonicalPaths.has(app.bundlePath)) continue;
    if (!deadline || deadline.aborted) break;
    try {
      const canonical = await cancellableRead(identityRuntime.realpath(app.bundlePath), deadline);
      addIdentity(app, canonical);
    } catch {
      signal.throwIfAborted();
    }
  }
  // Historical IDs need not be the current path after alias collapse. Reserve
  // every saved/ignored ID before admitting new paths, including unavailable apps.
  const reserved = new Set([...previous.map((app) => app.id), ...ignoredIDs]);
  const owners = new Map<string, AppRecord>();
  for (const app of previous) {
    const owner = owners.get(app.id);
    // Repair already-colliding snapshots in favor of the original moved app,
    // rather than transferring its saved preferences to the reused alias path.
    if (!owner || (owner.id === owner.bundlePath && app.id !== app.bundlePath)) {
      owners.set(app.id, app);
    }
  }
  const used = new Set<string>();
  const admit = (app: AppRecord, prior?: AppRecord): AppRecord => {
    let id = prior?.id ?? app.id;
    if (used.has(id) || (prior ? owners.get(id) !== prior : reserved.has(id))) {
      do {
        id = `app:${randomUUID()}`;
      } while (used.has(id) || reserved.has(id));
    }
    used.add(id);
    return id === app.id ? app : { ...app, id };
  };
  const replaced = new Set<AppRecord>();
  const ignored = new Set(ignoredIDs);
  const scannedApps = scanned.map((app) => {
    const canonical = canonicalPaths.get(app.bundlePath);
    const aliases = canonical ? (byCanonical.get(canonical) ?? []) : [];
    const samePath = previous.find((item) => item.bundlePath === app.bundlePath);
    const candidates = (samePath ? [samePath, ...aliases] : aliases).filter(
      (item) => owners.get(item.id) === item
    );
    // Preserve any proven alias's ignore preference, including already duplicated
    // snapshots. Reuse identity only; fresh metadata controls source invalidation.
    const prior = candidates.find((item) => ignored.has(item.id)) ?? candidates[0];
    for (const alias of aliases) replaced.add(alias);
    return admit(app, prior);
  });
  signal.throwIfAborted();
  return {
    scannedApps,
    retainedApps: retained.filter((app) => !replaced.has(app)).map((app) => admit(app, app))
  };
}

export const testingExports = { identityRuntime };
