// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { useEffect, useRef, useState } from "react";
import { ArrowLeft, ArrowRight, ArrowUpRight, X } from "lucide-react";
import defaultMark from "../../../assets/app-icon.icon/Assets/ChatGPT Image Oct 21, 2026, 10_19_50 PM.png";
import mark from "../../../assets/app-icon.icon/Assets/ChatGPT Image Oct 21, 2026, 10_19_53 PM.png";
import { baseline } from "../ipc";

const chapters = ["Welcome", "Your updates", "Make yourself at home"];

/** The welcome is a replaceable surface, not a modal over a live dashboard. */
export function Welcome({ onClose, revisit = false }: { onClose: () => void; revisit?: boolean }) {
  const [step, setStep] = useState(0);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState("");
  const [guideError, setGuideError] = useState("");
  const pending = useRef(false);
  const heading = useRef<HTMLHeadingElement>(null);

  const finish = async () => {
    if (pending.current) return;
    pending.current = true;
    setSaving(true);
    setSaveError("");
    try {
      if (!revisit) await baseline.updatePreferences({ welcomeDismissed: true });
      onClose();
    } catch {
      setSaveError("Your welcome preference couldn’t be saved. Please try again.");
    } finally {
      pending.current = false;
      setSaving(false);
    }
  };

  useEffect(() => {
    heading.current?.focus();
  }, [step]);

  return (
    <main
      className="welcome"
      aria-labelledby="welcome-title"
      onKeyDown={(event) => {
        if (event.key === "Escape") {
          event.preventDefault();
          void finish();
        }
      }}
    >
      <header className="welcome-topbar">
        <span>Baseline</span>
        <button
          className="welcome-close"
          aria-label={revisit ? "Close welcome" : "Skip welcome"}
          disabled={saving}
          onClick={() => void finish()}
        >
          <X size={17} aria-hidden="true" />
        </button>
      </header>
      <div className={`welcome-composition welcome-step-${step}`}>
        <div className="welcome-art" aria-hidden="true">
          <div className="welcome-halo" />
          <picture className="welcome-mark">
            <source media="(prefers-color-scheme: dark)" srcSet={mark} />
            <img src={defaultMark} alt="" draggable={false} />
          </picture>
          <div className="welcome-baseline" />
        </div>
        <section className="welcome-copy" key={step}>
          <p className="welcome-eyebrow">{chapters[step]}</p>
          <h1 id="welcome-title" ref={heading} tabIndex={-1}>
            {step === 0 ? (
              <>
                A little order.
                <br />A lighter Mac day.
              </>
            ) : step === 1 ? (
              <>
                Your apps.
                <br />A clearer picture.
              </>
            ) : (
              <>
                Right here.
                <br />
                When you need it.
              </>
            )}
          </h1>
          {step === 0 && (
            <p className="welcome-description">
              Welcome to Baseline. A considered place to find app updates and choose what happens
              next.
            </p>
          )}
          {step === 1 && (
            <>
              <p className="welcome-description">
                Find updates from the App Store, publishers, and apps you installed with Homebrew.
              </p>
              <div className="welcome-details">
                <p>
                  <strong>You choose the next step.</strong> Update with a supported tool, visit the
                  publisher, or open the app to use its own updater.
                </p>
                <p>
                  <strong>A check isn’t an install.</strong> Background checks find updates. You
                  decide when to act.
                </p>
              </div>
            </>
          )}
          {step === 2 && (
            <>
              <p className="welcome-description">
                Keep the full picture in the window, or check in from your menu bar. Make it yours
                in Settings.
              </p>
              <div className="welcome-details">
                <p>
                  <strong>No Baseline account needed.</strong> Preferences and history stay on this
                  Mac. Update checks contact public update sources.
                </p>
                <p>
                  Some updates need macOS App Management access. The optional guide explains how;
                  you can come back to it in Settings.
                </p>
                <button
                  className="welcome-guide"
                  onClick={() => {
                    setGuideError("");
                    void baseline
                      .permissionGuide("show")
                      .catch(() =>
                        setGuideError("The permission guide couldn’t open. Please try again.")
                      );
                  }}
                >
                  Help with permissions <ArrowUpRight size={13} aria-hidden="true" />
                </button>
              </div>
            </>
          )}
        </section>
      </div>
      <footer className="welcome-footer">
        <div
          className="welcome-progress"
          aria-label={`Introduction: step ${step + 1} of 3 — ${chapters[step]}`}
        >
          {chapters.map((chapter, index) => (
            <span key={chapter} className={index === step ? "active" : ""} />
          ))}
        </div>
        <div className="welcome-actions">
          {step > 0 && (
            <button
              className="welcome-back"
              disabled={saving}
              onClick={() => {
                setGuideError("");
                setStep(step - 1);
              }}
            >
              <ArrowLeft size={14} aria-hidden="true" /> Back
            </button>
          )}
          <button
            className="welcome-next"
            disabled={saving}
            onClick={() => (step < 2 ? setStep(step + 1) : void finish())}
          >
            {saving
              ? "Saving…"
              : step === 2
                ? revisit
                  ? "Back to Settings"
                  : "Open Baseline"
                : "Continue"}
            <ArrowRight size={15} aria-hidden="true" />
          </button>
        </div>
        {[saveError, guideError].filter(Boolean).map((message) => (
          <p key={message} className="welcome-error" role="alert">
            {message}
          </p>
        ))}
      </footer>
    </main>
  );
}
