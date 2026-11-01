// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { test, type Locator, type Page } from "@playwright/test";
import { writeFile } from "node:fs/promises";

export async function observeNotesKeys(page: Page, traceMarkers = false): Promise<void> {
  // Register before the flow begins; do not add layout reads around the key.
  await page.evaluate((markers) => {
    let keySequence = 0;
    const events: { snapshot: object; event: KeyboardEvent }[] = [];
    const identities = new WeakMap<Element, number>();
    let nextIdentity = 0;
    const identity = (element: Element) => {
      let value = identities.get(element);
      if (value === undefined) {
        value = ++nextIdentity;
        identities.set(element, value);
      }
      return value;
    };
    Object.assign(globalThis, {
      notesScrollKeys: () =>
        events.map(({ snapshot, event }) => ({
          ...snapshot,
          finalPrevented: event.defaultPrevented
        })),
      notesScrollIdentity: identity
    });
    for (const type of ["keydown", "keyup"]) {
      for (const capture of [true, false])
        window.addEventListener(
          type,
          (event) => {
            const key = event as KeyboardEvent;
            if (!["PageDown", "ArrowDown"].includes(key.key)) return;
            if (markers && capture && type === "keydown")
              performance.mark(`notes-key-${key.key}-${keySequence++}`);
            const target = key.target as Element | null;
            const entry = {
              type,
              phase: capture ? "capture" : "bubble",
              key: key.key,
              code: key.code,
              keyCode: key.keyCode,
              trusted: key.isTrusted,
              repeat: key.repeat,
              alt: key.altKey,
              ctrl: key.ctrlKey,
              meta: key.metaKey,
              shift: key.shiftKey,
              target: target?.getAttribute("aria-label"),
              tag: target?.tagName,
              objectIdentity: target ? identity(target) : null,
              active: document.activeElement === target,
              focused: document.hasFocus(),
              time: performance.now()
            };
            events.push({
              snapshot: { ...entry, preventedAtPhase: key.defaultPrevented },
              event: key
            });
          },
          capture
        );
    }
  }, traceMarkers);
}

export async function captureNotesScrollFailure(
  page: Page,
  notes: Locator,
  nativeState: () => Promise<unknown>
): Promise<void> {
  const evidence: Record<string, unknown> = {};
  const state = () =>
    notes.evaluate(
      (node) => {
        const identify = (element: Element) => ({
          objectIdentity: (
            globalThis as typeof globalThis & {
              notesScrollIdentity?: (element: Element) => number;
            }
          ).notesScrollIdentity?.(element),
          tag: element.tagName,
          id: element.id,
          label: element.getAttribute("aria-label"),
          className: element.className,
          connected: element.isConnected,
          rect: element.getBoundingClientRect().toJSON(),
          top: element.scrollTop,
          left: element.scrollLeft,
          height: element.scrollHeight,
          clientHeight: element.clientHeight,
          width: element.scrollWidth,
          clientWidth: element.clientWidth,
          overflowX: getComputedStyle(element).overflowX,
          overflowY: getComputedStyle(element).overflowY
        });
        const ancestors = [];
        for (let parent = node.parentElement; parent; parent = parent.parentElement)
          ancestors.push(identify(parent));
        return {
          target: identify(node),
          ancestors,
          active: document.activeElement ? identify(document.activeElement) : null,
          documentScroll: document.scrollingElement ? identify(document.scrollingElement) : null,
          windowScroll: { x: scrollX, y: scrollY },
          focused: document.hasFocus(),
          visibility: document.visibilityState,
          time: performance.now(),
          keys: (
            globalThis as typeof globalThis & { notesScrollKeys?: () => object[] }
          ).notesScrollKeys?.(),
          // CSS/Web Animations only; this does not expose Chromium scroll animation.
          animations: node.parentElement?.getAnimations().map((animation) => ({
            playState: animation.playState,
            currentTime: animation.currentTime
          }))
        };
      },
      undefined,
      { timeout: 1000 }
    );
  const frame = () =>
    page.evaluate(
      () =>
        new Promise<object>((resolve) => {
          const start = performance.now();
          let handle = 0;
          const timer = setTimeout(() => {
            cancelAnimationFrame(handle);
            resolve({ result: "timeout", elapsed: performance.now() - start });
          }, 500);
          handle = requestAnimationFrame((timestamp) => {
            clearTimeout(timer);
            resolve({ result: "frame", timestamp, elapsed: performance.now() - start });
          });
        })
    );
  try {
    evidence.originalFailure = await state();
    evidence.nativeAtFailure = await nativeState();
    evidence.firstFrame = await frame();
    evidence.afterFrameImmediate = await state();
    await page.waitForTimeout(250);
    evidence.afterFramePassive = await state();
    evidence.secondFrame = await frame();
    await page.waitForTimeout(250);
    evidence.afterSecondFramePassive = await state();
    // A screenshot forces frame production: only intervene AFTER preserving failure.
    const screenshotPath = test.info().outputPath("notes-after-original-failure.png");
    await page.screenshot({ path: screenshotPath, timeout: 5000 });
    await test.info().attach("notes-after-original-failure", {
      path: screenshotPath,
      contentType: "image/png"
    });
    evidence.afterScreenshotImmediate = await state();
    await page.waitForTimeout(250);
    evidence.afterScreenshotPassive = await state();
    await page.keyboard.press("PageDown");
    await page.waitForTimeout(250);
    evidence.secondPageDown = await state();
    await page.keyboard.press("ArrowDown");
    await page.waitForTimeout(250);
    evidence.arrowDown = await state();
    await notes.evaluate(
      (node) =>
        node.scrollTo({
          top: Math.min(node.clientHeight, node.scrollHeight - node.clientHeight),
          behavior: "instant"
        }),
      undefined,
      { timeout: 1000 }
    );
    evidence.instantProgrammaticProbe = await state();
  } catch (error) {
    evidence.probeError = String(error);
  }
  try {
    const body = JSON.stringify(evidence, null, 2);
    console.log(`NOTES_SCROLL_PROBES ${JSON.stringify(evidence)}`);
    const evidencePath = test.info().outputPath("notes-original-failure-probes.json");
    await writeFile(evidencePath, body);
    await test.info().attach("notes-original-failure-probes", {
      path: evidencePath,
      contentType: "application/json"
    });
  } catch {
    // Diagnostics must never replace the original assertion failure.
  }
}
