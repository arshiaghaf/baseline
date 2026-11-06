// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { spawn } from "node:child_process";
import path from "node:path";
import { performance } from "node:perf_hooks";
import { cliHelp, cliWantsJSON, parseCLIArguments } from "./arguments";
import { cliUserData } from "./endpoint";
import { sendCLIRequest } from "./client";
import { CLIError, cliExit, type CLIOperation, type CLIResponse } from "../shared/cli";
import packageJSON from "../../package.json";

import { human, humanWarnings } from "./presentation";

const pause = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));
const closedStreams = new Set<NodeJS.WriteStream>();
let outputFailed = false;
const write = (stream: NodeJS.WriteStream, content: string) => {
  if (!closedStreams.has(stream)) stream.write(content);
};

async function main(): Promise<void> {
  let json = cliWantsJSON(process.argv.slice(2));
  let operationID: string | undefined;
  let sessionID = "";
  let interrupted = false;
  let signalCode: number = cliExit.interrupted;
  const interrupt = new AbortController();
  const onInterrupt = () => {
    interrupted = true;
    signalCode = cliExit.interrupted;
    interrupt.abort(
      new CLIError(
        "interrupted",
        "Stopped waiting. Accepted work continues in Baseline.",
        signalCode
      )
    );
  };
  const onTerminate = () => {
    interrupted = true;
    signalCode = 143;
    interrupt.abort(
      new CLIError(
        "interrupted",
        "Stopped waiting. Accepted work continues in Baseline.",
        signalCode
      )
    );
  };
  process.on("SIGINT", onInterrupt);
  process.on("SIGTERM", onTerminate);
  const output = (response: CLIResponse) => {
    process.exitCode = response.exitCode || (outputFailed ? cliExit.failed : 0);
    const content = json ? `${JSON.stringify(response)}\n` : human(response);
    write(json || response.ok ? process.stdout : process.stderr, content);
    if (!json) write(process.stderr, humanWarnings(response));
  };
  try {
    const parsed = parseCLIArguments(process.argv.slice(2));
    json = parsed.json;
    if (parsed.local) {
      const text = parsed.local === "help" ? (parsed.help ?? cliHelp) : packageJSON.version;
      if (json)
        output({
          schemaVersion: 1,
          sessionID,
          ok: true,
          exitCode: 0,
          data: parsed.local === "help" ? { help: text } : { version: text }
        });
      else write(process.stdout, `${text}\n`);
      return;
    }
    const request = parsed.request!;
    operationID = request.operationID;
    const userData = cliUserData();
    const start = performance.now();
    const send = (r: Parameters<typeof sendCLIRequest>[1]) => {
      const remaining = parsed.timeoutMS - (performance.now() - start);
      if (remaining <= 0)
        throw new CLIError(
          "timeout",
          "Stopped waiting. Query the operation ID before retrying any submitted work.",
          cliExit.timeout
        );
      return sendCLIRequest(userData, r, {
        timeoutMS: Math.min(10_000, remaining),
        signal: interrupt.signal
      });
    };
    const checkInterrupt = () => {
      if (interrupted)
        throw new CLIError(
          "interrupted",
          "Stopped waiting. Accepted work continues in Baseline.",
          signalCode
        );
    };
    // Probe with a harmless read before launching. Never resend a mutation after
    // any transport uncertainty. Startup retries are exclusively status reads.
    let probe: CLIResponse | undefined;
    try {
      probe = await send({ schemaVersion: 1, command: "status" });
    } catch (error) {
      const code = (error as NodeJS.ErrnoException).code;
      if (!["ENOENT", "ECONNREFUSED"].includes(code ?? "")) throw error;
      const env = { ...process.env };
      delete env.ELECTRON_RUN_AS_NODE;
      delete env.NODE_OPTIONS;
      delete env.NODE_REPL_EXTERNAL_MODULE;
      const child = spawn(process.execPath, ["--baseline-cli-background"], {
        detached: true,
        stdio: "ignore",
        env,
        cwd: path.dirname(process.execPath)
      });
      let launchError: Error | undefined;
      child.once("error", (e) => {
        launchError = e;
      });
      child.unref();
      while (performance.now() - start < Math.min(parsed.timeoutMS, 15_000)) {
        checkInterrupt();
        if (launchError)
          throw new CLIError(
            "launch-failed",
            "Could not launch the packaged Baseline app.",
            cliExit.unavailable
          );
        await pause(100);
        try {
          probe = await send({ schemaVersion: 1, command: "status" });
          break;
        } catch (retryError) {
          if (
            !["ENOENT", "ECONNREFUSED"].includes((retryError as NodeJS.ErrnoException).code ?? "")
          )
            throw retryError;
        }
      }
    }
    if (!probe)
      throw new CLIError(
        "backend-unavailable",
        "Baseline did not start its CLI backend. Quit any older running copy, then update or restart the app.",
        cliExit.unavailable
      );
    sessionID = probe.sessionID;
    checkInterrupt();
    if (operationID && request.command !== "operation")
      write(process.stderr, `Operation: ${operationID}\n`);
    let response = await send(request);
    if (response.sessionID !== sessionID)
      throw new CLIError(
        "session-changed",
        "Baseline restarted. Inspect installed state before retrying.",
        cliExit.unavailable
      );
    let operation = (response.data as { operation?: CLIOperation } | undefined)?.operation;
    while (response.ok && operation && !operation.finishedAt && parsed.wait) {
      checkInterrupt();
      if (performance.now() - start >= parsed.timeoutMS)
        throw new CLIError(
          "timeout",
          "Stopped waiting. Accepted work continues; query the operation ID before retrying.",
          cliExit.timeout
        );
      await pause(200);
      response = await send({
        schemaVersion: 1,
        command: "operation",
        operationID: operation.id
      });
      if (response.sessionID !== sessionID)
        throw new CLIError(
          "session-changed",
          "Baseline restarted. Inspect installed state before retrying.",
          cliExit.unavailable
        );
      operation = (response.data as { operation?: CLIOperation } | undefined)?.operation;
    }
    if (operation?.finishedAt)
      response = { ...response, ok: operation.exitCode === 0, exitCode: operation.exitCode };
    output(response);
  } catch (error) {
    const e =
      error instanceof CLIError
        ? error
        : new CLIError(
            "unavailable",
            "Could not reach Baseline. Restart the app and run baseline doctor.",
            cliExit.unavailable
          );
    output({
      schemaVersion: 1,
      sessionID,
      ok: false,
      exitCode: e.exitCode,
      error: { code: e.code, message: e.message },
      ...(operationID
        ? {
            data: {
              operationID,
              outcome: "unknown-or-running",
              next: `baseline operation ${operationID} --json`
            }
          }
        : {})
    });
  } finally {
    process.removeListener("SIGINT", onInterrupt);
    process.removeListener("SIGTERM", onTerminate);
  }
}

for (const stream of [process.stdout, process.stderr])
  stream.on("error", (error: NodeJS.ErrnoException) => {
    closedStreams.add(stream);
    // A closed consumer stops presentation, not observation of accepted work.
    // Preserve failures, timeouts and signals, including errors discovered later.
    if (error.code !== "EPIPE") outputFailed = true;
    process.exitCode ||= outputFailed ? cliExit.failed : cliExit.success;
  });
void main();
