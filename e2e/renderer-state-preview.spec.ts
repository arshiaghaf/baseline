// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { _electron as electron, expect, test } from "@playwright/test";
import { execFile, type ChildProcess } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { defaultPersistedSnapshot } from "../src/shared/domain";

let entry: string;
test.beforeAll(async () => {
  const result = await promisify(execFile)(
    process.execPath,
    ["scripts/preview-release-notes.mjs", "--prepare"],
    { timeout: 60_000 }
  );
  entry = JSON.parse(result.stdout.trim().split("\n").at(-1)!).entry;
});

for (const route of ["main", "menubar"]) {
  test(`retains search drafts and sole modal ownership in hidden Electron (${route})`, async () => {
    const directory = await mkdtemp(path.join(os.tmpdir(), "baseline-renderer-state-"));
    let application: Awaited<ReturnType<typeof electron.launch>> | undefined;
    let ownedProcess: ChildProcess | undefined;
    try {
      await writeFile(
        path.join(directory, "snapshot.json"),
        JSON.stringify({
          ...defaultPersistedSnapshot(),
          operationFailures: [
            {
              id: "fixture-failure",
              entityID: "app:fixture",
              operation: "update",
              reason: "command",
              status: 1,
              occurredAt: "2026-11-06T12:00:00Z"
            }
          ]
        })
      );
      await writeFile(path.join(directory, "notes.json"), "{}");
      const env = Object.fromEntries(
        Object.entries({
          ...process.env,
          BASELINE_NOTES_PREVIEW_ROOT: process.cwd(),
          BASELINE_NOTES_PREVIEW_PROFILE: path.join(directory, "profile"),
          BASELINE_NOTES_PREVIEW_SNAPSHOT: path.join(directory, "snapshot.json"),
          BASELINE_NOTES_PREVIEW_FIXTURE_NOTES: path.join(directory, "notes.json"),
          BASELINE_NOTES_PREVIEW_ROUTE: route,
          BASELINE_NOTES_PREVIEW_HIDDEN: "1"
        }).filter(
          (entry): entry is [string, string] =>
            typeof entry[1] === "string" && entry[0] !== "ELECTRON_RUN_AS_NODE"
        )
      );
      application = await electron.launch({ args: [entry], env });
      ownedProcess = application.process();
      console.log(`Owned hidden state fixture PID ${ownedProcess.pid}: ${entry}`);
      const page = await application.firstWindow();
      const session = await page.context().newCDPSession(page);
      await session.send("Emulation.setFocusEmulationEnabled", { enabled: true });
      await expect.poll(() => page.evaluate(() => document.hasFocus())).toBe(true);
      await page.locator(".operation-failure summary").click();
      const reportTrigger = page.getByRole("button", { name: "Report issue", exact: true });
      await reportTrigger.click();
      await page.keyboard.press("Meta+f");
      await page.keyboard.press("Meta+k");
      await expect(page.getByRole("dialog")).toHaveCount(1);
      await expect(page.getByRole("dialog", { name: "Report issue" })).toBeVisible();
      expect(
        await page.locator(".action-surface").evaluate((node) => node.hasAttribute("inert"))
      ).toBe(true);
      await page.getByRole("button", { name: "Open on GitHub" }).focus();
      await page.keyboard.press("Tab");
      await expect(page.getByLabel("Report text")).toBeFocused();
      await page.keyboard.press("Escape");
      await expect(reportTrigger).toBeFocused();

      await page.getByRole("button", { name: "Search", exact: true }).click();
      await application.evaluate(({ BrowserWindow }) => {
        const window = BrowserWindow.getAllWindows()[0]!;
        const send = window.webContents.send.bind(window.webContents);
        const messages: unknown[][] = [];
        // Delay only this disposable fixture's snapshot delivery, not real IPC admission.
        window.webContents.send = (channel, ...args) => {
          if (channel === "baseline:snapshotChanged") messages.push(structuredClone(args));
          else send(channel, ...args);
        };
        (
          globalThis as typeof globalThis & { releaseStateSnapshot?: () => number }
        ).releaseStateSnapshot = () => {
          const next = messages.shift();
          if (next) send("baseline:snapshotChanged", ...next);
          return messages.length;
        };
      });
      const input = page.getByPlaceholder("Search");
      await input.pressSequentially("abc");
      await expect(input).toHaveValue("abc");
      await input.press("ArrowLeft");
      await application.evaluate(() =>
        (
          globalThis as typeof globalThis & { releaseStateSnapshot: () => number }
        ).releaseStateSnapshot()
      );
      await expect(input).toHaveValue("abc");
      expect(await input.evaluate((node: HTMLInputElement) => node.selectionStart)).toBe(2);
      await application.evaluate(() => {
        const release = (globalThis as typeof globalThis & { releaseStateSnapshot: () => number })
          .releaseStateSnapshot;
        while (release() > 0) {
          /* Drain this fixture's remaining echoes. */
        }
      });
      await expect(input).toHaveValue("abc");
      await page.getByRole("button", { name: "Clear Search" }).click();
      await expect(input).toHaveValue("");
      await expect(input).toBeFocused();
      expect(
        await application.evaluate(({ BrowserWindow }) =>
          BrowserWindow.getAllWindows().every(
            (window) => !window.isVisible() && !window.isFocused()
          )
        )
      ).toBe(true);
    } finally {
      if (application) {
        await application.close();
        expect(ownedProcess!.exitCode !== null || ownedProcess!.signalCode !== null).toBe(true);
      }
      await rm(directory, { recursive: true, force: true });
    }
  });
}
