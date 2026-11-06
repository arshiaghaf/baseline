// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import {
  cliFailureDescription,
  type CLIOperation,
  type CLIResponse,
  type CLITarget
} from "../shared/cli";
import type { OperationFailure } from "../shared/operationFailures";

/** Visible escapes keep terminal controls from disguising text, without changing JSON identities. */
export const clean = (value: string): string =>
  Array.from(value, (character) =>
    /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u.test(character)
      ? `\\u{${character.codePointAt(0)!.toString(16)}}`
      : character
  ).join("");

type HumanData = {
  targets?: CLITarget[];
  target?: CLITarget;
  operation?: CLIOperation;
  diagnostics?: string;
  capabilities?: Record<string, unknown>;
  exitCodes?: Record<string, number>;
  failures?: OperationFailure[];
  operationID?: string;
  next?: string;
  outcome?: string;
  planID?: string;
  effects?: string;
  version?: string;
  lastExplicitCheckAt?: string | null;
  lastRefreshAt?: string | null;
  homebrewCheckStatus?: string;
  appDiscoveryComplete?: boolean;
  refreshing?: boolean;
  refreshFailed?: boolean;
  freshForUpdates?: boolean;
  notices?: string[];
};

const health = (data: HumanData) =>
  `Last scan: ${clean(data.lastRefreshAt ?? "Never")}\nApp discovery: ${data.appDiscoveryComplete ? "complete" : "not complete"}\nHomebrew check: ${clean(data.homebrewCheckStatus ?? "unknown")}\n${data.freshForUpdates ? "A recent explicit check is available; individual target protections still apply." : "Run baseline check before updating."}\n`;

export function humanWarnings(response: CLIResponse): string {
  const data = response.data as HumanData | undefined;
  if (!data || (!data.targets && !data.target && !data.version && !data.diagnostics)) return "";
  return [
    ...(data.refreshing ? ["A scan is running; these results may be incomplete."] : []),
    ...(data.refreshFailed ? ["The last scan failed; recorded versions may be stale."] : []),
    ...(data.appDiscoveryComplete === false ? ["App discovery is incomplete."] : []),
    ...(data.homebrewCheckStatus === "incomplete" ? ["Homebrew inventory is incomplete."] : []),
    ...(data.notices ?? [])
  ]
    .map((notice) => `Warning: ${clean(notice)}\n`)
    .join("");
}

export function human(response: CLIResponse): string {
  const data = response.data as HumanData | undefined;
  if (response.error)
    return `${clean(response.error.message)}\n${data?.operationID ? `Operation: ${clean(data.operationID)}\n` : ""}${data?.outcome ? `Outcome: ${clean(data.outcome)}\n` : ""}${data?.next ? `Next: ${clean(data.next)}\n` : ""}`;
  if (data?.operation) {
    const op = data.operation;
    return `${clean(op.id)}  ${clean(op.state)}${op.message ? `\n${clean(op.message)}` : ""}\n${op.results.map((r) => `${clean(r.id)}  ${clean(r.status)}${r.message ? ` — ${clean(r.message)}` : ""}\n`).join("")}`;
  }
  if (data?.targets || data?.target) {
    const targets = data.targets ?? [data.target!];
    return `${targets.length ? "ID\tNAME\tSOURCE\tINSTALLED\tAVAILABLE\tACTION\tCHECK\tCHECKED AT\n" : "No installed targets are recorded. Run baseline check.\n"}${targets.map((t) => [t.id, t.name, t.source, t.installedVersion, t.availableVersion ?? "—", t.action, t.checkStatus ?? "unknown", t.checkedAt ?? "Never"].map(clean).join("\t")).join("\n")}\n${targets
      .filter((t) => t.reason)
      .map((t) => `${clean(t.id)}: ${clean(t.reason!)}\n`)
      .join(
        ""
      )}${health(data)}${data.planID ? `Plan: ${clean(data.planID)}\n${clean(data.effects ?? "")}\n` : ""}`;
  }
  if (data?.diagnostics) {
    const capabilities = Object.entries(data.capabilities ?? {})
      .map(
        ([key, value]) =>
          `${clean(key)}: ${clean(Array.isArray(value) ? value.join(", ") : String(value))}\n`
      )
      .join("");
    const exits = Object.entries(data.exitCodes ?? {})
      .map(([key, value]) => `${value}: ${clean(key)}`)
      .join(", ");
    const failures = (data.failures ?? [])
      .map(
        (failure) =>
          `${clean(failure.entityID)} (${clean(failure.operation)}): ${clean(cliFailureDescription(failure))}${failure.entityID === "homebrew:maintenance" ? " Inspect Homebrew before taking further action; do not repeat a verified installed update to repair a later step." : " Inspect installed state before retrying."}\n`
      )
      .join("");
    return `${data.diagnostics.split("\n").map(clean).join("\n")}\n${health(data)}Capabilities:\n${capabilities}Exit codes: ${exits}\n${failures ? `Recorded failures (may predate this request):\n${failures}` : ""}`;
  }
  if (data?.version)
    return `Baseline ${clean(data.version)}\nLast explicit check: ${clean(data.lastExplicitCheckAt ?? "Never")}\n${health(data)}`;
  return `${JSON.stringify(response.data, null, 2)}\n`;
}
