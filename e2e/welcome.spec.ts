// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { _electron as electron, expect, test } from "@playwright/test";
import { execFile } from "node:child_process";
import { mkdtemp, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { cleanupApplications } from "./applicationCleanup";

// Uses the production renderer/preload in an activation-prohibited Electron
// fixture. No production app, inventory, Keychain, permission pane or network.
test("welcome chapters, reduced motion, keyboard, interruption and replay", async () => {
  const testInfo = test.info();
  const prepared = await promisify(execFile)(
    process.execPath,
    ["scripts/preview-release-notes.mjs", "--prepare"],
    { cwd: process.cwd() }
  );
  const entry = JSON.parse(prepared.stdout.trim().split("\n").at(-1)!).entry as string;
  const directory = await mkdtemp(path.join(os.tmpdir(), "baseline-welcome-rendered-"));
  await writeFile(
    path.join(directory, "snapshot.json"),
    JSON.stringify({ welcomeDismissed: false })
  );
  await writeFile(path.join(directory, "notes.json"), "{}");
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    BASELINE_NOTES_PREVIEW_ROOT: process.cwd(),
    BASELINE_NOTES_PREVIEW_PROFILE: path.join(directory, "profile"),
    BASELINE_NOTES_PREVIEW_SNAPSHOT: path.join(directory, "snapshot.json"),
    BASELINE_NOTES_PREVIEW_FIXTURE_NOTES: path.join(directory, "notes.json"),
    BASELINE_NOTES_PREVIEW_HIDDEN: "1"
  };
  delete env.ELECTRON_RUN_AS_NODE;
  const application = await electron.launch({
    args: [entry, "-AppleShowScrollBars", "Always"],
    env: Object.fromEntries(
      Object.entries(env).filter((entry): entry is [string, string] => typeof entry[1] === "string")
    )
  });
  const child = application.process();
  console.log(`Owned hidden welcome PID ${child.pid}: ${child.spawnfile}`);
  try {
    const page = await application.firstWindow();
    const capture = async (name: string) => {
      const icon = page.locator(".welcome-mark img");
      if (await icon.count()) {
        await expect
          .poll(() =>
            icon.evaluate((node: HTMLImageElement) => {
              const source = node.parentElement!.querySelector("source")!;
              const expected = new URL(
                matchMedia("(prefers-color-scheme: dark)").matches ? source.srcset : node.src,
                document.baseURI
              ).href;
              return node.currentSrc === expected && node.complete && node.naturalWidth > 0;
            })
          )
          .toBe(true);
        await icon.evaluate((node: HTMLImageElement) => node.decode());
      }
      await page.screenshot({ path: testInfo.outputPath(name) });
    };
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    const session = await page.context().newCDPSession(page);
    await session.send("Emulation.setFocusEmulationEnabled", { enabled: true });
    await expect(page.getByRole("button", { name: "Skip welcome" })).toBeVisible();
    await expect(page.getByRole("heading", { level: 1 })).toBeFocused();
    await expect(
      page.getByRole("img", { name: "Introduction: step 1 of 3 — Welcome" })
    ).toBeVisible();
    // Default motion finishes rather than looping forever.
    await expect
      .poll(() =>
        page
          .locator(".welcome-mark")
          .evaluate((node) =>
            node.getAnimations().every((animation) => animation.playState === "finished")
          )
      )
      .toBe(true);
    for (const colorScheme of ["light", "dark"] as const) {
      await page.emulateMedia({ colorScheme, reducedMotion: "reduce" });
      await capture(`welcome-${colorScheme}.png`);
    }
    await page.keyboard.press("Tab");
    await expect(page.getByRole("button", { name: "Continue" })).toBeFocused();
    await page.keyboard.press("Enter");
    await expect(page.getByRole("heading", { level: 1 })).toContainText("Your apps.");
    await expect(page.getByRole("heading", { level: 1 })).toBeFocused();
    await capture("updates-dark.png");
    await page.reload();
    await expect(page.getByRole("heading", { level: 1 })).toContainText("A little order.");
    await page.getByRole("button", { name: "Continue" }).click();
    await page.getByRole("button", { name: "Continue" }).click();
    await capture("ready-dark.png");
    await application.evaluate(({ BrowserWindow }) =>
      BrowserWindow.getAllWindows()[0]!.setContentSize(660, 620)
    );
    for (const colorScheme of ["light", "dark"] as const) {
      await page.emulateMedia({ colorScheme, reducedMotion: "reduce" });
      await capture(`ready-minimum-${colorScheme}.png`);
    }
    const geometry = await page.locator(".welcome-next").boundingBox();
    const viewport = await page.evaluate(() => ({ width: innerWidth, height: innerHeight }));
    expect(geometry!.y + geometry!.height).toBeLessThanOrEqual(viewport.height);
    expect(
      await page.locator(".welcome").evaluate((node) => node.scrollWidth <= node.clientWidth)
    ).toBe(true);
    expect(
      await page.locator(".welcome-mark").evaluate((node) => getComputedStyle(node).animationName)
    ).toBe("none");
    await page.getByRole("button", { name: "Open Baseline" }).click();
    await expect(page.locator(".welcome")).toHaveCount(0);
    await expect(page.locator(".topbar h1")).toBeFocused();
    await page.reload();
    await expect(page.locator(".welcome")).toHaveCount(0);
    await page.evaluate(() => {
      window.location.hash = "/settings";
    });
    await page.addStyleTag({
      content:
        ".settings-content { overflow-y: scroll; scrollbar-gutter: stable; } .settings-content::-webkit-scrollbar { width: 12px; }"
    });
    const gutter = () =>
      page
        .locator(".settings-content")
        .evaluate((node: HTMLElement) => node.offsetWidth - node.clientWidth);
    await expect.poll(gutter).toBeGreaterThan(0);
    await page.getByRole("button", { name: "Show welcome" }).click();
    await expect(page.getByRole("button", { name: "Close welcome" })).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(page.getByRole("button", { name: "Show welcome" })).toBeFocused();
    await expect
      .poll(() =>
        page
          .locator(".settings-topbar")
          .evaluate((node) => node.style.getPropertyValue("--settings-scrollbar-width"))
      )
      .toBe(`${await gutter()}px`);
    await page.screenshot({ path: testInfo.outputPath("settings-revisit.png") });
    await page.evaluate(() => {
      window.location.hash = "/menubar";
    });
    await expect(page.locator(".welcome")).toHaveCount(0);
    expect(
      await application.evaluate(({ BrowserWindow }) =>
        BrowserWindow.getAllWindows().every((window) => !window.isVisible() && !window.isFocused())
      )
    ).toBe(true);
    expect(errors).toEqual([]);
    await writeFile(
      testInfo.outputPath("verification.json"),
      JSON.stringify(
        {
          hidden: true,
          activationProhibited: true,
          productionRenderer: true,
          minimumSize: viewport,
          pid: child.pid,
          executable: child.spawnfile,
          pageErrors: errors
        },
        null,
        2
      )
    );
  } finally {
    await cleanupApplications([application]);
    expect(child.exitCode !== null || child.signalCode !== null).toBe(true);
  }
});
