// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { expect, it } from "vitest";
import { HomebrewCaskClient } from "../src/main/homebrewCaskClient";
import { version } from "../src/shared/version";

it.each([false, true])(
  "preserves independent app, identifier and installer evidence (strict=%s)",
  (strictCatalogue) => {
    const fixtures = [
      {
        token: "explicit-app",
        artifacts: [
          { app: ["Explicit.app"] },
          { pkg: ["Helper.pkg"] },
          { uninstall: [{ quit: "com.example.helper" }] }
        ]
      },
      {
        token: "explicit-id",
        artifacts: [{ pkg: ["Installer.pkg"] }],
        metadata: { bundle_ids: ["com.example.b", "com.example.a"] },
        uninstall: { quit: "com.example.helper", login_item: "Identified" }
      },
      {
        token: "installer-app",
        artifacts: [
          { pkg: ["Installer.pkg"] },
          { binary: ["helper", { target: "helper-target" }] }
        ],
        uninstall: { quit: ["com.example.installer"], login_item: ["Installer", " "] }
      },
      {
        token: "installer-cli",
        artifacts: [
          { pkg: ["Installer.pkg"] },
          { binary: ["helper", { target: "helper-target" }] }
        ],
        uninstall: { quit: "com.example.helper" }
      },
      {
        token: "renamed-target",
        artifacts: [{ pkg: ["Installer.pkg", { target: "Renamed.app" }] }],
        uninstall: { quit: "com.example.helper" }
      },
      {
        token: "quit-only",
        artifacts: [{ pkg: ["Installer.pkg"] }],
        uninstall: { quit: ["com.example.z", "com.example.a"] }
      }
    ];
    const client = new HomebrewCaskClient();
    const index = client.parseIndex(
      Buffer.from(JSON.stringify(fixtures.map((entry) => ({ ...entry, version: "2.0" })))),
      { strictCatalogue }
    );
    expect(
      Object.values(index.byToken).map((entry) => ({
        token: entry.token,
        presentation: entry.presentation,
        ids: entry.bundleIdentifiers,
        inferred: entry.inferredBundleIdentifiers,
        names: entry.appBundleNames
      }))
    ).toEqual([
      {
        token: "explicit-app",
        presentation: "app",
        ids: [],
        inferred: undefined,
        names: ["explicit.app"]
      },
      {
        token: "explicit-id",
        presentation: "app",
        ids: ["com.example.a", "com.example.b"],
        inferred: undefined,
        names: ["identified.app"]
      },
      {
        token: "installer-app",
        presentation: "app",
        ids: [],
        inferred: ["com.example.installer"],
        names: ["installer.app"]
      },
      { token: "installer-cli", presentation: "cli", ids: [], inferred: undefined, names: [] },
      {
        token: "renamed-target",
        presentation: "app",
        ids: [],
        inferred: undefined,
        names: ["renamed.app"]
      },
      {
        token: "quit-only",
        presentation: "package",
        ids: [],
        inferred: ["com.example.a", "com.example.z"],
        names: []
      }
    ]);
    expect(Object.keys(index.byBundleIdentifier).sort()).toEqual([
      "com.example.a",
      "com.example.b"
    ]);
    expect(
      client.lookupUpdate("com.example.installer", "Helper.app", version("1"), index)
    ).toBeUndefined();
    expect(client.lookupUpdate(undefined, "Installer.app", version("1"), index)).toMatchObject({
      token: "installer-app"
    });
    expect(
      client.lookupUpdate(undefined, "Installer.app", version("1"), index, () => false)
    ).toBeUndefined();
    expect(
      client
        .searchCasks("installer", index, new Set())
        .map(({ token }) => token)
        .sort()
    ).toEqual(["installer-app", "installer-cli"]);
  }
);

it.each([false, true])(
  "keeps bounded installed evidence independent of oversized optional siblings (optional first=%s)",
  (optionalFirst) => {
    const optional = Object.fromEntries(
      Array.from({ length: 2048 }, (_, index) => [
        `optional-${index}`,
        { children: Array.from({ length: 20 }, () => ({ text: "optional" })) }
      ])
    );
    const evidence = {
      token: "installed-app",
      version: "2.0",
      artifacts: [
        { app: ["Original.app", { target: "/Applications/Installed.app" }] },
        { uninstall: [{ delete: "/Applications/Unrelated.app", quit: "com.example.helper" }] }
      ],
      bundleIdentifier: "com.example.installed"
    };
    const entry = optionalFirst ? { ...optional, ...evidence } : { ...evidence, ...optional };
    const client = new HomebrewCaskClient();
    const index = client.parseIndex(Buffer.from(JSON.stringify([entry])));
    expect(index.byToken["installed-app"]).toMatchObject({
      presentation: "app",
      bundleIdentifiers: ["com.example.installed"],
      appBundleNames: ["installed.app", "original.app", "unrelated.app"],
      installedAppPaths: ["/Applications/Installed.app"]
    });
    expect(index.byToken["installed-app"]?.inferredBundleIdentifiers).toBeUndefined();
    expect(
      client.lookupUpdate("com.example.installed", "Installed.app", version("1"), index)
    ).toMatchObject({ token: "installed-app" });
    expect(
      Object.keys(
        client.parseIndex(Buffer.from(JSON.stringify([entry, { token: "healthy" }])), {
          strictCatalogue: true
        }).byToken
      )
    ).toEqual(["healthy"]);
  }
);
