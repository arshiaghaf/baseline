// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";

function fixture(body: string) {
  const root = mkdtempSync(path.join(tmpdir(), "baseline-preview-install-"));
  for (const name of ["installed.app", "source.app", "transaction"]) {
    mkdirSync(path.join(root, name, "Contents/MacOS"), { recursive: true });
  }
  writeFileSync(path.join(root, "installed.app/marker"), "previous");
  writeFileSync(path.join(root, "source.app/marker"), "preview");
  const result = spawnSync(
    "bash",
    [
      "-c",
      `set -euo pipefail
source "$HELPER"
INSTALL_PATH="$FIXTURE/installed.app"
TRANSACTION_DIR="$FIXTURE/transaction"
PREVIEW_PID=""
trap cleanup_preview_install EXIT
# Installation tests use real temporary files, with all signing/launch/host effects mocked.
verify_preview_bundle() { [[ -f "$1/marker" ]]; }
require_app_stopped() { return 0; }
smoke_launch_app() { return 0; }
ditto() { cp -R "$1" "$2"; }
${body}`
    ],
    {
      env: { ...process.env, HELPER: path.resolve("scripts/preview-install.sh"), FIXTURE: root },
      encoding: "utf8"
    }
  );
  return {
    result,
    exists: (name: string) => existsSync(path.join(root, name)),
    read: (name: string) => readFileSync(path.join(root, name), "utf8"),
    dispose: () => rmSync(root, { recursive: true, force: true })
  };
}

function check(body: string, assertions: (value: ReturnType<typeof fixture>) => void) {
  const value = fixture(body);
  try {
    assertions(value);
  } finally {
    value.dispose();
  }
}

describe("staged preview replacement", () => {
  it.each([0, 5000])(
    "refuses a running target in a large process list (target index %s)",
    (targetIndex) => {
      check(
        `
source "$HELPER"
verify_preview_bundle() { [[ -f "$1/marker" ]]; }
smoke_launch_app() { echo UNEXPECTED_LAUNCH; }
running_executable="$(canonical_executable "$INSTALL_PATH")"
ps() {
  for ((i=0;i<=5000;i++)); do
    if [[ "$i" == ${targetIndex} ]]; then printf '%s\n' "$running_executable";
    else printf '/fixture/worker-%08d/Contents/MacOS/Worker\n' "$i"; fi
  done
}
install_preview "$FIXTURE/source.app"`,
        (value) => {
          expect(value.result.status).toBe(1);
          expect(value.read("installed.app/marker")).toBe("previous");
          expect(value.exists("transaction/previous/installed.app")).toBe(false);
          expect(value.result.stdout).not.toContain("UNEXPECTED_LAUNCH");
        }
      );
    }
  );

  it("refuses replacement when process enumeration fails", () => {
    check(
      `
source "$HELPER"
verify_preview_bundle() { [[ -f "$1/marker" ]]; }
smoke_launch_app() { echo UNEXPECTED_LAUNCH; }
ps() { printf '/fixture/partial\n'; return 1; }
install_preview "$FIXTURE/source.app"`,
      (value) => {
        expect(value.result.status).toBe(1);
        expect(value.read("installed.app/marker")).toBe("previous");
        expect(value.exists("transaction/previous/installed.app")).toBe(false);
      }
    );
  });

  it("keeps the installed bundle intact when copying fails after a partial write", () => {
    check(
      'ditto() { mkdir "$2"; printf partial > "$2/marker"; return 74; }; install_preview "$FIXTURE/source.app"',
      (value) => {
        expect(value.result.status).toBe(1);
        expect(value.read("installed.app/marker")).toBe("previous");
        expect(value.read("transaction/staged/installed.app/marker")).toBe("partial");
      }
    );
  });

  it("rejects an invalid staged bundle before removing the previous app", () => {
    check(
      'verify_preview_bundle() { [[ "$1" != "$TRANSACTION_DIR/staged/installed.app" ]]; }; install_preview "$FIXTURE/source.app"',
      (value) => {
        expect(value.result.status).toBe(1);
        expect(value.read("installed.app/marker")).toBe("previous");
      }
    );
  });

  it.each(["return 74", "exit 143"])(
    "retains the verified new bundle on promotion failure (%s)",
    (failure) => {
      check(
        `mv() { if [[ "$1" == -n && "$2" == "$TRANSACTION_DIR/staged/installed.app" ]]; then ${failure}; fi; command mv "$@"; }; install_preview "$FIXTURE/source.app"`,
        (value) => {
          expect(value.result.status).not.toBe(0);
          expect(value.exists("installed.app")).toBe(false);
          expect(value.read("transaction/staged/installed.app/marker")).toBe("preview");
          expect(value.exists("transaction/previous")).toBe(false);
        }
      );
    }
  );

  it("leaves the old bundle intact when staging is interrupted", () => {
    check(
      'ditto() { cp -R "$1" "$2"; exit 143; }; install_preview "$FIXTURE/source.app"',
      (value) => {
        expect(value.result.status).toBe(143);
        expect(value.read("installed.app/marker")).toBe("previous");
        expect(value.read("transaction/staged/installed.app/marker")).toBe("preview");
        expect(value.exists("transaction/previous")).toBe(false);
      }
    );
  });

  it("does not promote or launch when removing the old bundle fails", () => {
    check(
      'rm() { return 74; }; smoke_launch_app() { echo UNEXPECTED_LAUNCH; }; install_preview "$FIXTURE/source.app"',
      (value) => {
        expect(value.result.status).toBe(1);
        expect(value.read("installed.app/marker")).toBe("previous");
        expect(value.read("transaction/staged/installed.app/marker")).toBe("preview");
        expect(value.result.stdout).not.toContain("UNEXPECTED_LAUNCH");
      }
    );
  });

  it("preserves unrelated profile data through replacement and launch failure", () => {
    check(
      'printf saved > "$FIXTURE/profile-data"; smoke_launch_app() { return 1; }; install_preview "$FIXTURE/source.app"',
      (value) => {
        expect(value.result.status).toBe(1);
        expect(value.read("profile-data")).toBe("saved");
        expect(value.read("installed.app/marker")).toBe("preview");
        expect(value.exists("transaction/previous")).toBe(false);
      }
    );
  });

  it("does not overwrite a target that appears during promotion", () => {
    check(
      `mv() { if [[ "$2" == "$TRANSACTION_DIR/staged/installed.app" ]]; then mkdir "$INSTALL_PATH"; printf concurrent > "$INSTALL_PATH/marker"; fi; command mv "$@"; }; install_preview "$FIXTURE/source.app"`,
      (value) => {
        expect(value.result.status).toBe(1);
        expect(value.read("installed.app/marker")).toBe("concurrent");
        expect(value.exists("transaction/previous")).toBe(false);
      }
    );
  });

  it("retains the new installation after a failed launch without retaining the old bundle", () => {
    check('smoke_launch_app() { return 1; }; install_preview "$FIXTURE/source.app"', (value) => {
      expect(value.result.status).toBe(1);
      expect(value.read("installed.app/marker")).toBe("preview");
      expect(value.exists("transaction/previous")).toBe(false);
    });
  });

  it("installs a verified copy without keeping an old bundle", () => {
    check('install_preview "$FIXTURE/source.app"', (value) => {
      expect(value.result.status).toBe(0);
      expect(value.read("installed.app/marker")).toBe("preview");
      expect(value.exists("transaction/previous")).toBe(false);
    });
  });
});

function processFixture(body: string) {
  return spawnSync("bash", ["-c", `set -euo pipefail; source "$HELPER"; ${body}`], {
    env: { ...process.env, HELPER: path.resolve("scripts/preview-install.sh") },
    encoding: "utf8"
  });
}

describe("preview process ownership", () => {
  it("refuses a running target and never signals an existing user process", () => {
    const result = processFixture(`
canonical_executable() { printf '/fixture/installed.app/Contents/MacOS/Baseline\n'; }
ps() { printf '/fixture/other.app/Contents/MacOS/Baseline\n/fixture/installed.app/Contents/MacOS/Baseline\n'; }
kill() { echo UNEXPECTED_SIGNAL; }
require_app_stopped /fixture/installed.app`);
    expect(result.status).toBe(1);
    expect(result.stderr).toContain("Quit /fixture/installed.app");
    expect(result.stdout).not.toContain("UNEXPECTED_SIGNAL");
  });

  it("ignores a namesake at another executable path", () => {
    const result = processFixture(`
canonical_executable() { printf '/fixture/installed.app/Contents/MacOS/Baseline\n'; }
ps() { printf '/fixture/other.app/Contents/MacOS/Baseline\n'; }
require_app_stopped /fixture/installed.app`);
    expect(result.status).toBe(0);
  });

  it.each(["new-start /owned/Baseline", "old-start /other/Baseline"])(
    "never signals a reused or changed PID (%s)",
    (identity) => {
      const result = processFixture(`
PREVIEW_PID=123; PREVIEW_IDENTITY='old-start /owned/Baseline'
ps() { printf '%s\n' '${identity}'; }
kill() { echo UNEXPECTED_SIGNAL; }
stop_owned_preview`);
      expect(result.status).toBe(1);
      expect(result.stdout).not.toContain("UNEXPECTED_SIGNAL");
    }
  );

  it("sends only TERM to its matching owned PID, with no force fallback", () => {
    const result = processFixture(`
PREVIEW_PID=123; PREVIEW_IDENTITY='old-start /owned/Baseline'
ps() { printf '%s\n' "$PREVIEW_IDENTITY"; }
kill() { printf 'signal %s\n' "$*"; }
sleep() { :; }
stop_owned_preview`);
    expect(result.status).toBe(1);
    expect(result.stdout.trim()).toBe("signal -TERM 123");
    expect(result.stderr).toContain("No force signal was sent");
  });

  it.each(["before TERM", "after TERM"])(
    "retains ownership when process inspection fails %s and exit is unconfirmed",
    (phase) => {
      for (const probeStatus of [1, 2, 127]) {
        const result = processFixture(`
PREVIEW_PID=123; PREVIEW_IDENTITY='old-start /owned/Baseline'; signalled=false
ps() {
  if [[ '${phase}' == 'before TERM' || "$signalled" == true ]]; then return 1; fi
  printf '%s\\n' "$PREVIEW_IDENTITY"
}
process_has_exited() { return ${probeStatus}; }
kill() { printf 'signal %s\\n' "$*"; signalled=true; }
if stop_owned_preview; then echo FALSE_EXIT; fi
[[ "$PREVIEW_PID" == 123 ]]`);
        expect(result.status).toBe(0);
        expect(result.stdout).not.toContain("FALSE_EXIT");
        expect(result.stdout).toBe(phase === "after TERM" ? "signal -TERM 123\n" : "");
        expect(result.stderr).toContain("could not be confirmed");
      }
    }
  );

  it.each(["alive", "ESRCH", "EPERM", "unknown"])(
    "only treats ESRCH as a confirmed exit (%s)",
    (outcome) => {
      const result = processFixture(`
node() {
  command node -e '
    const script = process.argv.splice(1, 1)[0];
    process.kill = (pid, signal) => {
      if (pid !== 123 || signal !== 0) throw new Error("unexpected probe");
      if ("${outcome}" === "alive") return true;
      throw Object.assign(new Error("synthetic probe"), { code: "${outcome}" });
    };
    eval(script);
  ' "$2" "$3"
}
process_has_exited 123`);
      expect(result.status).toBe(outcome === "ESRCH" ? 0 : 1);
    }
  );

  it("accepts a separately confirmed exit without signalling", () => {
    const result = processFixture(`
PREVIEW_PID=123; PREVIEW_IDENTITY='old-start /owned/Baseline'
ps() { return 1; }
process_has_exited() { return 0; }
kill() { echo UNEXPECTED_SIGNAL; }
stop_owned_preview
[[ -z "$PREVIEW_PID" ]]`);
    expect(result.status).toBe(0);
    expect(result.stdout).not.toContain("UNEXPECTED_SIGNAL");
  });

  it("confirms an owned smoke process exited after graceful shutdown", () => {
    const result = processFixture(`
PREVIEW_PID=123; PREVIEW_IDENTITY='old-start /owned/Baseline'; stopped=false
ps() { if [[ "$stopped" == true ]]; then return 1; fi; printf '%s\\n' "$PREVIEW_IDENTITY"; }
kill() { printf 'signal %s\\n' "$*"; stopped=true; }
process_has_exited() { [[ "$stopped" == true ]]; }
stop_owned_preview
[[ -z "$PREVIEW_PID" ]]`);
    expect(result.status).toBe(0);
    expect(result.stdout.trim()).toBe("signal -TERM 123");
  });

  it("waits for its launched child to exec and leaves a successful installed preview running", () => {
    const result = processFixture(`
canonical_executable() { printf '/usr/bin/true\n'; }
require_app_stopped() { :; }
TRANSACTION_DIR="$(mktemp -d)"
trap 'rm -f "$TRANSACTION_DIR/preview-mounted.log" "$TRANSACTION_DIR/preview-installed.log" "$TRANSACTION_DIR/probed"; rmdir "$TRANSACTION_DIR"' EXIT
ps() {
  if [[ -f "$TRANSACTION_DIR/probed" ]]; then printf 'start /usr/bin/true\n';
  else touch "$TRANSACTION_DIR/probed"; printf 'start /bin/bash\n'; fi
}
sleep() { :; }
kill() { echo UNEXPECTED_SIGNAL; }
smoke_launch_app /fixture/app fixture true
[[ -z "$PREVIEW_PID" ]]`);
    expect(result.status).toBe(0);
    expect(result.stdout).toContain("Smoke launch succeeded");
    expect(result.stdout).not.toContain("UNEXPECTED_SIGNAL");
  });

  it("rejects a post-launch namesake race instead of accepting another PID", () => {
    const result = processFixture(`
canonical_executable() { printf '/usr/bin/true\n'; }
require_app_stopped() { :; }
TRANSACTION_DIR="$(mktemp -d)"; trap 'rm -f "$TRANSACTION_DIR/preview-mounted.log" "$TRANSACTION_DIR/preview-installed.log"; rmdir "$TRANSACTION_DIR"' EXIT
ps() { printf 'start /different/Baseline\n'; }
sleep() { :; }
smoke_launch_app /fixture/app fixture`);
    expect(result.status).toBe(1);
    expect(result.stdout).not.toContain("succeeded");
  });
});

describe("preview bundle verification", () => {
  it.each(["valid", "signature", "version", "missing hash", "invalid signing"])(
    "checks copied bundle integrity (%s)",
    (failure) => {
      const root = mkdtempSync(path.join(tmpdir(), "baseline-preview-signature-"));
      try {
        const app = path.join(root, "copy.app");
        mkdirSync(path.join(app, "Contents/MacOS"), { recursive: true });
        writeFileSync(path.join(app, "Contents/MacOS/Baseline"), "fixture", { mode: 0o755 });
        const result = processFixture(`
codesign() { [[ '${failure}' != 'invalid signing' ]]; }
bundle_property() {
  case "$2" in
    CFBundleIdentifier) echo com.arshiaghaf.baseline;;
    CFBundleExecutable) echo Baseline;;
    *) if [[ '${failure}' == version && "$1" != /reference.app ]]; then echo changed; else echo 1; fi;;
  esac
}
bundle_hash() {
  if [[ '${failure}' == 'missing hash' ]]; then return 0; fi
  if [[ '${failure}' == signature && "$1" != /reference.app ]]; then echo other; else echo expected; fi
}
verify_preview_bundle '${app}' /reference.app`);
        expect(result.status).toBe(failure === "valid" ? 0 : 1);
      } finally {
        rmSync(root, { recursive: true, force: true });
      }
    }
  );
});

describe("preview exit cleanup", () => {
  it.each([
    [0, 0, 0],
    [0, 1, 1],
    [74, 1, 74],
    [130, 1, 130],
    [143, 0, 143]
  ])("preserves exit %s with cleanup %s as %s", (initial, cleanup, expected) => {
    const result = processFixture(`
cleanup_preview() { echo cleanup; return ${cleanup}; }
trap 'finish_preview $?' EXIT
exit ${initial}`);
    expect(result.status).toBe(expected);
    expect(result.stdout.trim()).toBe("cleanup");
  });
});
