// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync, copyFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";

function prepareNotes(changelog: string): string {
  const root = mkdtempSync(path.join(tmpdir(), "baseline-release-notes-"));
  try {
    mkdirSync(path.join(root, "scripts"));
    copyFileSync(
      path.resolve("scripts/prepare-unsigned-release.sh"),
      path.join(root, "scripts/prepare-unsigned-release.sh")
    );
    // Exercise the real release entry point without packaging an application.
    writeFileSync(
      path.join(root, "scripts/create-unsigned-dmg.sh"),
      '#!/usr/bin/env bash\nset -eu\nmkdir -p dist\nprintf fixture > "dist/Baseline-$1-unsigned.dmg"\n',
      { mode: 0o755 }
    );
    for (const file of ["package.json", "package-lock.json"]) {
      writeFileSync(path.join(root, file), JSON.stringify({ version: "0.8.0" }));
    }
    writeFileSync(path.join(root, "CHANGELOG.md"), changelog);
    execFileSync("bash", ["scripts/prepare-unsigned-release.sh", "0.8.0"], {
      cwd: root,
      stdio: "pipe"
    });
    return readFileSync(path.join(root, "dist/Baseline-0.8.0-unsigned-release-notes.md"), "utf8");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

interface ReleaseFixture {
  tagName: string;
  name: string;
  body: string;
  assets: { name: string }[];
}

const requiredAssets = ["Baseline-0.8.0-unsigned.dmg", "Baseline-0.8.0-unsigned.dmg.sha256"];

function checkRelease(overrides: Partial<ReleaseFixture> = {}, tag = "v0.8.0") {
  const root = mkdtempSync(path.join(tmpdir(), "baseline-release-assets-"));
  try {
    const bin = path.join(root, "bin");
    mkdirSync(bin);
    writeFileSync(path.join(bin, "gh"), '#!/usr/bin/env bash\ncat "$RELEASE_FIXTURE"\n', {
      mode: 0o755
    });
    const releasePath = path.join(root, "release.json");
    writeFileSync(
      releasePath,
      JSON.stringify({
        tagName: "v0.8.0",
        name: "Baseline 0.8.0",
        body: "### Fixed\n\n- Release entry.\n",
        assets: requiredAssets.map((name) => ({ name })),
        ...overrides
      })
    );
    return spawnSync("bash", [path.resolve("scripts/check-release-assets.sh"), tag], {
      cwd: root,
      encoding: "utf8",
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, RELEASE_FIXTURE: releasePath }
    });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

describe("release asset and note contract", () => {
  it.each(["Highlights", "Added", "Fixed"])("accepts generated %s-only notes", (heading) => {
    const notes = prepareNotes(`## 0.8.0 — 2026-10-18\n\n### ${heading}\n\n- Release entry.\n`);
    expect(checkRelease({ body: notes }).status).toBe(0);
  });

  it.each(["", "### Internal\n- Entry.", "### Highlights extra\n- Entry."])(
    "rejects notes without a supported exact heading: %j",
    (body) => {
      const result = checkRelease({ body });
      expect(result.status).toBe(1);
      expect(result.stdout).toContain("Release notes must contain");
    }
  );

  it.each(["early", "late"])("finds required assets in a large list (%s)", (position) => {
    const padding = Array.from({ length: 12000 }, (_, index) => ({
      name: `unrelated-artifact-${index}.zip`
    }));
    const required = requiredAssets.map((name) => ({ name }));
    const assets = position === "early" ? [...required, ...padding] : [...padding, ...required];
    expect(checkRelease({ assets }).status).toBe(0);
  });

  it.each(["early", "late"])("accepts a supported heading in large notes (%s)", (position) => {
    const padding = "- Release detail.\n".repeat(20000);
    const body = position === "early" ? `### Fixed\n${padding}` : `${padding}### Fixed\n`;
    expect(checkRelease({ body }).status).toBe(0);
  });

  it.each([
    "# Baseline",
    "## What's Changed",
    "## Download",
    "## SHA-256",
    "## Install",
    "## Build Note"
  ])("rejects forbidden section %s", (heading) => {
    const result = checkRelease({ body: `### Fixed\n- Entry.\n${heading}\n` });
    expect(result.status).toBe(1);
    expect(result.stdout).toContain(`unexpected section: ${heading}`);
  });

  it.each(["early", "late"])("rejects a forbidden section in large notes (%s)", (position) => {
    const padding = "- Release detail.\n".repeat(20000);
    // Keep the supported heading last to independently exercise forbidden-section admission.
    const body =
      position === "early"
        ? `## Download\n${padding}### Fixed\n`
        : `${padding}## Download\n### Fixed\n`;
    const result = checkRelease({ body });
    expect(result.status).toBe(1);
    expect(result.stdout).toContain("unexpected section: ## Download");
  });

  it.each(requiredAssets)("rejects missing exact required asset %s", (missing) => {
    const assets = requiredAssets
      .filter((name) => name !== missing)
      .concat(`${missing}.extra`)
      .map((name) => ({ name }));
    const result = checkRelease({ assets });
    expect(result.status).toBe(1);
    expect(result.stdout).toContain(`missing asset: ${missing}`);
  });

  it.each([
    [{ tagName: "v0.8.1" }, "Release tag is"],
    [{ name: "Baseline Preview" }, "Release title is"]
  ] as const)("rejects inconsistent release metadata %j", (overrides, message) => {
    const result = checkRelease(overrides);
    expect(result.status).toBe(1);
    expect(result.stdout).toContain(message);
  });

  it("rejects an invalid requested tag", () => {
    const result = checkRelease({}, "v0.8.0-preview");
    expect(result.status).toBe(1);
    expect(result.stdout).toContain("Tag must look like");
  });
});

describe("release note extraction", () => {
  it("preserves Highlights and detailed sections in order, including links", () => {
    const notes = `### Highlights

- **Find updates sooner.** Results appear during refresh. ([#1](https://github.com/example/app/pull/1))

### Added

- New refresh control.

### Fixed

- Recover failed checks.
`;
    expect(prepareNotes(`# Changelog\n\n## 0.8.0 — 2026-10-18\n\n${notes}`)).toBe(notes);
  });

  it("keeps older Added-only entries without adding a compatibility notice", () => {
    const notes = "### Added\n\n- Existing release entry.\n";
    expect(prepareNotes(`## 0.8.0 — 2026-10-18\n\n${notes}`)).toBe(notes);
  });

  it("excludes neighboring releases and unsupported subsections", () => {
    expect(
      prepareNotes(`## 0.9.0 — Unreleased

### Highlights

- Future entry.

## 0.8.0 — 2026-10-18

### Highlights

- Current highlight.

### Internal

- Private preparation detail.

### Fixed

- Current fix.

## 0.7.1 — 2026-10-16

### Fixed

- Previous fix.
`)
    ).toBe("### Highlights\n\n- Current highlight.\n\n### Fixed\n\n- Current fix.\n");
  });

  it("still rejects an Unreleased section instead of preparing artifacts", () => {
    expect(() => prepareNotes("## 0.8.0 — Unreleased\n\n### Highlights\n\n- Pending.\n")).toThrow();
  });
});
