// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { test, type Page } from "@playwright/test";
import { mkdir, writeFile } from "node:fs/promises";

function beforeDeadline<T>(operation: () => Promise<T>, deadline: number): Promise<T> {
  const remaining = deadline - Date.now();
  if (remaining <= 0) return Promise.reject(new Error("Trace diagnostic deadline exceeded"));
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error("Trace diagnostic deadline exceeded")),
      remaining
    );
    // Keep both handlers attached even if the deadline wins; no orphan rejection.
    Promise.resolve()
      .then(operation)
      .then(
        (value) => {
          clearTimeout(timer);
          resolve(value);
        },
        (error: unknown) => {
          clearTimeout(timer);
          reject(error);
        }
      );
  });
}

export async function startNotesScrollTrace(page: Page) {
  const info = test.info();
  const setupDeadline = Date.now() + 5000;
  const session = await beforeDeadline(() => page.context().newCDPSession(page), setupDeadline);
  const requested = [
    "input",
    "blink",
    "cc",
    "viz",
    "benchmark",
    "latencyInfo",
    "devtools.timeline",
    "blink.user_timing",
    "disabled-by-default-blink.debug"
  ];
  let categories: string[] = [];
  try {
    const available = await beforeDeadline(
      () => session.send("Tracing.getCategories"),
      setupDeadline
    );
    categories = requested.filter((category) => available.categories.includes(category));
    // No screenshots, JS sampling or pre-key frame/geometry intervention.
    await beforeDeadline(
      () =>
        session.send("Tracing.start", {
          transferMode: "ReturnAsStream",
          streamFormat: "json",
          streamCompression: "none",
          traceConfig: {
            recordMode: "recordContinuously",
            traceBufferSizeInKb: 32768,
            includedCategories: categories,
            enableSampling: false,
            enableSystrace: false
          }
        }),
      setupDeadline
    );
  } catch (error) {
    await beforeDeadline(() => session.detach(), Date.now() + 1000).catch(() => undefined);
    throw error;
  }
  let finished = false;
  return {
    async finish(outcome: "pass" | "failure" | "interrupted"): Promise<void> {
      if (finished) return;
      finished = true;
      // Eight seconds for all collection/storage, then two seconds shared by cleanup.
      const collectionDeadline = Date.now() + 8000;
      const keep = outcome !== "pass" || info.repeatEachIndex === 0;
      let stream: string | undefined;
      let timer: ReturnType<typeof setTimeout> | undefined;
      let listener: ((event: { stream?: string; dataLossOccurred?: boolean }) => void) | undefined;
      try {
        const complete = new Promise<{ stream?: string; dataLossOccurred?: boolean }>((resolve) => {
          listener = (event) => {
            clearTimeout(timer);
            resolve(event);
          };
          // Resolve on timeout; a failed Tracing.end cannot orphan a rejection.
          timer = setTimeout(() => resolve({}), 5000);
          session.once("Tracing.tracingComplete", listener);
        });
        await beforeDeadline(() => session.send("Tracing.end"), collectionDeadline);
        const completed = await beforeDeadline(() => complete, collectionDeadline);
        stream = completed.stream;
        if (!stream) throw new Error("Trace did not return a stream within five seconds");
        if (!keep) return;
        const chunks: Buffer[] = [];
        let bytes = 0;
        while (true) {
          const part = await beforeDeadline(
            () => session.send("IO.read", { handle: stream!, size: 65536 }),
            collectionDeadline
          );
          const chunk = Buffer.from(part.data, part.base64Encoded ? "base64" : "utf8");
          bytes += chunk.length;
          if (bytes > 64 * 1024 * 1024) throw new Error("Trace exceeds 64 MiB collection limit");
          chunks.push(chunk);
          if (part.eof) break;
        }
        const body = Buffer.concat(chunks);
        const summary = {
          outcome,
          mode: process.env.BASELINE_NOTES_DIAGNOSTIC_MODE,
          repeat: info.repeatEachIndex,
          bytes,
          categories,
          dataLossOccurred: completed.dataLossOccurred ?? false,
          note: "Parse the retained trace to verify event availability before inferring absence. A frame callback is not presentation proof."
        };
        await beforeDeadline(() => mkdir(info.outputDir, { recursive: true }), collectionDeadline);
        const tracePath = info.outputPath("notes-input-scroll.trace.json");
        const summaryPath = info.outputPath("notes-input-scroll.trace-summary.json");
        await beforeDeadline(() => writeFile(tracePath, body), collectionDeadline);
        await beforeDeadline(
          () => writeFile(summaryPath, JSON.stringify(summary, null, 2)),
          collectionDeadline
        );
        console.log(`NOTES_TRACE_SUMMARY ${JSON.stringify(summary)}`);
        await beforeDeadline(
          () =>
            info.attach("notes-input-scroll-trace", {
              path: tracePath,
              contentType: "application/json"
            }),
          collectionDeadline
        );
        await beforeDeadline(
          () =>
            info.attach("notes-input-scroll-trace-summary", {
              path: summaryPath,
              contentType: "application/json"
            }),
          collectionDeadline
        );
      } catch (error) {
        const details = { outcome, error: String(error) };
        console.log(`NOTES_TRACE_ERROR ${JSON.stringify(details)}`);
        // Best effort only: storage failure must not replace the original assertion.
        try {
          await beforeDeadline(
            () => mkdir(info.outputDir, { recursive: true }),
            collectionDeadline
          );
          await beforeDeadline(
            () => writeFile(info.outputPath("notes-trace-error.json"), JSON.stringify(details)),
            collectionDeadline
          );
        } catch {
          /* Console fallback remains available. */
        }
      } finally {
        clearTimeout(timer);
        if (listener) session.off("Tracing.tracingComplete", listener);
        const cleanupDeadline = Date.now() + 2000;
        await beforeDeadline(
          () =>
            Promise.allSettled([
              ...(stream
                ? [Promise.resolve().then(() => session.send("IO.close", { handle: stream! }))]
                : []),
              Promise.resolve().then(() => session.detach())
            ]),
          cleanupDeadline
        ).catch(() => undefined);
      }
    }
  };
}
