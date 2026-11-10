// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { randomUUID } from "node:crypto";
import { CLIError, cliExit, validateCLIRequest, type CLIRequest } from "../shared/cli";

export const cliHelp = `Usage: baseline <command> [options]

  status                     Show backend version, freshness and active work
  list                       List installed apps/packages with exact target IDs
  inspect <id>               Inspect one exact target
  check                      Scan and explicitly revalidate update metadata
  update <id>... --dry-run    Preview exact targets and receive a plan ID
  update <id>... --yes        Apply exact targets through the shared app backend
  operation <uuid>           Inspect work accepted by the current app session
  doctor                     Show diagnostics, capabilities and exit codes

Options:
  --json                     One versioned JSON response on stdout
  --interactive              Allow cask authorization and open app handoffs
  --expect-plan <id>         Apply only if a dry-run plan still matches
  --operation-id <uuid>      Reuse an identical request in this app session
  --no-wait                  Return as soon as check/update is accepted
  --wait                     Wait for an operation command to finish
  --timeout <seconds>        Stop waiting after 1–3600 seconds (default 300)
  --                         Treat remaining arguments as literal target IDs
  --help, -h                 Show help without launching Baseline
  --version                  Show CLI version without launching Baseline

Use baseline help <command> or baseline <command> --help for command help.
Value options also accept --option=value.

Run check before updating. Ignored/pinned apps and Baseline itself are protected.
Homebrew can update dependencies and perform its normal cleanup. App handoffs
require finishing the installation yourself; opening one is never success.
Ctrl-C and timeouts stop waiting; accepted work continues. Save the operation ID
and query it before retrying. Unknown IDs after restart do not prove failure.
`;

const commands = ["status", "list", "inspect", "check", "update", "operation", "doctor"];
const usages: Record<string, string> = {
  status: "status [--json]",
  list: "list [--json]",
  inspect: "inspect <id> [--json]",
  check: "check [--no-wait] [--operation-id <uuid>] [--timeout <seconds>] [--json]",
  update:
    "update <id>... (--dry-run | --yes) [--interactive] [--expect-plan <id>] [--operation-id <uuid>] [--no-wait] [--timeout <seconds>] [--json]",
  operation: "operation <uuid> [--wait] [--timeout <seconds>] [--json]",
  doctor: "doctor [--json]"
};
export function cliWantsJSON(args: string[]): boolean {
  const end = args.indexOf("--");
  return args.slice(0, end < 0 ? args.length : end).includes("--json");
}
const commandHelp = (command: string) =>
  `Usage: baseline ${usages[command]}\n\n${
    cliHelp
      .split("\n")
      .find((line) => line.trimStart().startsWith(`${command} `))
      ?.trim() ?? ""
  }\n\n${command === "update" ? "Preview with --dry-run, then use --yes to apply exact IDs from list. Casks and app handoffs require --interactive. Homebrew may update dependencies and perform normal cleanup.\n" : ""}${["check", "update", "operation"].includes(command) ? "Timeout is 1–3600 seconds (default 300). Stopping a wait does not cancel accepted work; query the operation ID before retrying.\n" : ""}Use baseline --help for all commands and options.\n`;

export function parseCLIArguments(args: string[]): {
  request?: CLIRequest;
  json: boolean;
  wait: boolean;
  timeoutMS: number;
  local?: "help" | "version";
  help?: string;
} {
  const result = { json: false, wait: true, timeoutMS: 300_000 };
  const positional: string[] = [];
  const options: Partial<CLIRequest> = {};
  const seen = new Set<string>();
  let literal = false;
  for (let i = 0; i < args.length; i++) {
    const token = args[i]!;
    if (token === "--" && !literal) {
      literal = true;
      continue;
    }
    if (!literal && token.startsWith("-")) {
      const equals = token.indexOf("=");
      const arg = equals < 0 ? token : token.slice(0, equals);
      const inlineValue = equals < 0 ? undefined : token.slice(equals + 1);
      const key = arg === "-h" ? "--help" : arg;
      if (seen.has(key))
        throw new CLIError("duplicate-option", `Option supplied twice: ${arg}`, cliExit.usage);
      seen.add(key);
      if (["--timeout", "--expect-plan", "--operation-id"].includes(arg)) {
        const value = inlineValue ?? args[++i];
        if (!value || value.startsWith("--"))
          throw new CLIError("missing-value", `Missing value for ${arg}.`, cliExit.usage);
        if (arg === "--timeout") {
          if (!/^\d+$/u.test(value) || Number(value) < 1 || Number(value) > 3600)
            throw new CLIError(
              "invalid-timeout",
              "Timeout must be an integer from 1 to 3600 seconds.",
              cliExit.usage
            );
          result.timeoutMS = Number(value) * 1000;
        } else if (arg === "--expect-plan") options.expectPlan = value;
        else options.operationID = value;
        continue;
      }
      if (inlineValue !== undefined)
        throw new CLIError(
          "invalid-options",
          `Option does not take a value: ${arg}.`,
          cliExit.usage
        );
      if (arg === "--json") {
        result.json = true;
        continue;
      }
      if (key === "--help" || arg === "--version") continue;
      if (arg === "--wait") {
        result.wait = true;
        continue;
      }
      if (arg === "--no-wait") {
        result.wait = false;
        continue;
      }
      const boolean = {
        "--dry-run": "dryRun",
        "--yes": "yes",
        "--interactive": "interactive"
      } as const;
      if (arg in boolean) {
        options[boolean[arg as keyof typeof boolean]] = true;
        continue;
      }
      throw new CLIError(
        "unknown-option",
        `Unknown option: ${arg}. Run baseline --help.`,
        cliExit.usage
      );
    }
    positional.push(token);
  }
  let command = positional.shift();
  if (command === "help") {
    command = positional.shift();
    seen.add("--help");
    if (positional.length)
      throw new CLIError("invalid-targets", "help takes at most one command.", cliExit.usage);
  }
  if (command && !commands.includes(command))
    throw new CLIError(
      "unknown-command",
      `Unknown command: ${command}. Run baseline --help.`,
      cliExit.usage
    );
  if (args.length === 0 || seen.has("--help"))
    return { ...result, local: "help", help: command ? commandHelp(command) : cliHelp };
  if (seen.has("--version")) {
    if (command || [...seen].some((key) => !["--version", "--json"].includes(key)))
      throw new CLIError(
        "invalid-options",
        "--version does not take a command or other options.",
        cliExit.usage
      );
    return { ...result, local: "version" };
  }
  if (command === "operation" && options.operationID)
    throw new CLIError(
      "invalid-options",
      "operation takes its UUID as a positional argument.",
      cliExit.usage
    );
  if (seen.has("--wait") && (command !== "operation" || seen.has("--no-wait")))
    throw new CLIError(
      "invalid-options",
      "--wait applies only to operation, without --no-wait.",
      cliExit.usage
    );
  if (command === "operation" && !seen.has("--wait")) result.wait = false;
  const request = validateCLIRequest({
    schemaVersion: 1,
    command,
    ...options,
    ...(command === "operation"
      ? { operationID: positional.shift() }
      : positional.length
        ? { ids: positional }
        : {})
  });
  if (command === "operation" && positional.length)
    throw new CLIError("invalid-targets", "operation takes one UUID.", cliExit.usage);
  if (
    (!result.wait || seen.has("--timeout")) &&
    !["check", "update", "operation"].includes(request.command)
  )
    throw new CLIError(
      "invalid-options",
      "Wait options apply to check, update and operation.",
      cliExit.usage
    );
  if ((request.command === "check" || request.command === "update") && !request.dryRun)
    request.operationID ??= randomUUID();
  return { ...result, request };
}
