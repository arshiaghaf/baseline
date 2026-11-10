// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { baseline } from "../ipc";
import type { HomebrewManagedItem } from "../../shared/domain";

export function performHomebrewUpdateAllForItems(items: Pick<HomebrewManagedItem, "id">[]): void {
  void baseline.performHomebrewUpdateAll(items.map((item) => item.id));
}

export function toggleCollapsedSection(kind: "app" | "homebrew", sectionID: string): void {
  void baseline.toggleCollapsedSection(kind, sectionID);
}
