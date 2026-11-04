// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, expect, it, vi } from "vitest";
import { Welcome } from "../src/renderer/components/Welcome";
import type { BaselineAPI } from "../src/shared/ipc";

beforeEach(() => {
  window.baseline = {
    updatePreferences: vi.fn(async () => {}),
    permissionGuide: vi.fn(async () => ({}))
  } as unknown as BaselineAPI;
});

it("moves focus with chapters, goes back, and opens permissions only on request", async () => {
  const close = vi.fn();
  render(<Welcome onClose={close} />);
  expect(screen.getByRole("img", { name: "Introduction: step 1 of 3 — Welcome" })).toBeVisible();
  expect(screen.getByRole("heading", { level: 1 })).toHaveFocus();
  fireEvent.click(screen.getByRole("button", { name: "Continue" }));
  expect(screen.getByRole("heading", { level: 1 })).toHaveTextContent("Your updates, together");
  expect(screen.getByRole("heading", { level: 1 })).toHaveFocus();
  fireEvent.click(screen.getByRole("button", { name: "Back" }));
  expect(screen.getByRole("heading", { level: 1 })).toHaveTextContent("Welcome to Baseline");
  fireEvent.click(screen.getByRole("button", { name: "Continue" }));
  fireEvent.click(screen.getByRole("button", { name: "Continue" }));
  expect(window.baseline.permissionGuide).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button", { name: "Help with permissions" }));
  await waitFor(() => expect(window.baseline.permissionGuide).toHaveBeenCalledWith("show"));
  expect(window.baseline.permissionGuide).not.toHaveBeenCalledWith("settings");
  expect(window.baseline.updatePreferences).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button", { name: "Open Baseline" }));
  await waitFor(() => expect(close).toHaveBeenCalledOnce());
  expect(window.baseline.updatePreferences).toHaveBeenCalledWith({ welcomeDismissed: true });
});

it("keeps failed dismissal retryable and coalesces Escape while saving", async () => {
  const close = vi.fn();
  let reject!: (error: Error) => void;
  vi.mocked(window.baseline.updatePreferences).mockImplementationOnce(
    () =>
      new Promise((_resolve, fail) => {
        reject = fail;
      })
  );
  render(<Welcome onClose={close} />);
  fireEvent.keyDown(screen.getByRole("main"), { key: "Escape" });
  fireEvent.keyDown(screen.getByRole("main"), { key: "Escape" });
  expect(window.baseline.updatePreferences).toHaveBeenCalledOnce();
  expect(close).not.toHaveBeenCalled();
  await act(async () => reject(new Error("disk unavailable")));
  expect(screen.getByRole("alert")).toHaveTextContent("couldn’t be saved");
  fireEvent.click(screen.getByRole("button", { name: "Skip welcome" }));
  await waitFor(() => expect(close).toHaveBeenCalledOnce());
  expect(screen.queryByRole("alert")).not.toBeInTheDocument();
});

it("replays without rewriting preferences and recovers permission-guide failures", async () => {
  const close = vi.fn();
  vi.mocked(window.baseline.permissionGuide).mockRejectedValueOnce(new Error("unavailable"));
  render(<Welcome revisit onClose={close} />);
  fireEvent.click(screen.getByRole("button", { name: "Continue" }));
  fireEvent.click(screen.getByRole("button", { name: "Continue" }));
  fireEvent.click(screen.getByRole("button", { name: "Help with permissions" }));
  await screen.findByRole("alert");
  fireEvent.click(screen.getByRole("button", { name: "Help with permissions" }));
  await waitFor(() => expect(screen.queryByRole("alert")).not.toBeInTheDocument());
  fireEvent.click(screen.getByRole("button", { name: "Back to Settings" }));
  expect(close).toHaveBeenCalledOnce();
  expect(window.baseline.updatePreferences).not.toHaveBeenCalled();
});

it("retains the motion pause across chapters and resumes on request", () => {
  render(<Welcome onClose={vi.fn()} />);
  fireEvent.click(screen.getByRole("button", { name: "Pause motion" }));
  fireEvent.click(screen.getByRole("button", { name: "Continue" }));
  expect(screen.getByRole("main")).toHaveAttribute("data-motion-paused", "true");
  fireEvent.click(screen.getByRole("button", { name: "Resume motion" }));
  expect(screen.getByRole("main")).toHaveAttribute("data-motion-paused", "false");
  expect(window.baseline.updatePreferences).not.toHaveBeenCalled();
});
