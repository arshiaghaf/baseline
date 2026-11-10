// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only
import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "e2e",
  testMatch: "welcome.spec.ts",
  timeout: 60_000,
  workers: 1,
  reporter: [["list"]]
});
