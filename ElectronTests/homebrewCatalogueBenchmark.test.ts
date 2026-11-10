// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

// @vitest-environment node

import { createHash } from "node:crypto";
import { performance } from "node:perf_hooks";
import { expect, it } from "vitest";
import { HomebrewCaskClient } from "../src/main/homebrewCaskClient";
import { version } from "../src/shared/version";

// Opt-in synchronous parsing probe; timings are observations, never CI thresholds.
it.skipIf(process.env.BASELINE_CATALOGUE_BENCHMARK !== "1")(
  "measures catalogue decoding with complete indexes and actionable update results",
  () => {
    const count = 6000;
    const data = Buffer.from(
      JSON.stringify(
        Array.from({ length: count }, (_, index) => ({
          token: `fixture-${index}`,
          version: "2.0,200",
          homepage: "https://example.com",
          artifacts:
            index % 3 === 0
              ? [{ app: [`Fixture ${index}.app`] }, { bundle_id: `com.example.fixture-${index}` }]
              : index % 3 === 1
                ? [
                    { pkg: [`Fixture${index}.pkg`] },
                    {
                      uninstall: [
                        { login_item: `Fixture ${index}`, quit: `com.example.fixture-${index}` }
                      ]
                    }
                  ]
                : [{ binary: [`fixture-${index}`] }],
          variations: Array.from({ length: 8 }, (_, variation) => ({
            platform: `platform-${variation}`,
            download: { url: "https://example.com/download", sha256: "a".repeat(64) },
            depends_on: { macos: [">=", "13"] }
          }))
        }))
      )
    );
    const rows = [];
    for (const strictCatalogue of [false, true]) {
      const samples = [];
      let digest = "";
      for (let sample = 0; sample < 6; sample++) {
        const client = new HomebrewCaskClient();
        const started = performance.now();
        const index = client.parseIndex(data, { strictCatalogue });
        const elapsed = performance.now() - started;
        expect(Object.keys(index.byToken)).toHaveLength(count);
        expect(Object.keys(index.byBundleIdentifier)).toHaveLength(count / 3);
        expect(Object.keys(index.byAppBundleName)).toHaveLength((count * 2) / 3);
        const actionable = Array.from({ length: count }, (_, item) =>
          client.lookupUpdate(
            `com.example.fixture-${item}`,
            `Fixture ${item}.app`,
            version("1.0"),
            index,
            (token) => token === `fixture-${item}`
          )
        ).filter((result) => result !== undefined);
        expect(actionable).toHaveLength((count * 2) / 3);
        expect(actionable[0]).toMatchObject({ token: "fixture-0", remoteVersion: version("2.0") });
        expect(actionable.at(-1)?.token).toBe(`fixture-${count - 2}`);
        const resultDigest = createHash("sha256")
          .update(JSON.stringify({ index, actionable }))
          .digest("hex");
        if (digest) expect(resultDigest).toBe(digest);
        digest = resultDigest;
        if (sample > 0) samples.push(elapsed);
      }
      rows.push({
        strictCatalogue,
        samples: samples.map((value) => Number(value.toFixed(2))),
        medianMilliseconds: Number([...samples].sort((a, b) => a - b)[2]!.toFixed(2)),
        resultSHA256: digest
      });
    }
    process.stdout.write(
      `${JSON.stringify({
        note: "Synthetic catalogue parsing only; excludes IO and total refresh latency.",
        node: process.version,
        platform: `${process.platform}/${process.arch}`,
        entries: count,
        actionableUpdates: (count * 2) / 3,
        bytes: data.byteLength,
        rows
      })}\n`
    );
  },
  60_000
);
