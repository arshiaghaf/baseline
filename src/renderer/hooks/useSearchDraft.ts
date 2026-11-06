// SPDX-FileCopyrightText: 2026 Arshia Ghaf
// SPDX-License-Identifier: GPL-3.0-only

import { useEffect, useRef, useState } from "react";
import type { BaselineSnapshot } from "../../shared/domain";
import { baseline } from "../ipc";

/** Keep edits synchronous; snapshots acknowledge edits without rolling the caret backwards. */
export function useSearchDraft(snapshot: BaselineSnapshot) {
  const [text, setText] = useState(snapshot.searchText);
  const [error, setError] = useState(false);
  const clientID = useRef<string>(undefined);
  const sequence = useRef(0);
  const composing = useRef(false);
  const errorOwner = useRef<string | undefined>(undefined);

  useEffect(() => {
    if (composing.current) return;
    const requestID = snapshot.searchTextRequestID;
    if (clientID.current && requestID?.startsWith(`${clientID.current}:`)) {
      if (requestID !== `${clientID.current}:${sequence.current}`) return;
    }
    errorOwner.current = requestID;
    setText(snapshot.searchText);
    setError(false);
  }, [snapshot.searchText, snapshot.searchTextRequestID]);

  const submit = (value: string) => {
    clientID.current ??= crypto.randomUUID();
    const requestID = `${clientID.current}:${++sequence.current}`;
    errorOwner.current = requestID;
    setError(false);
    void Promise.resolve(baseline.setSearchText(value, requestID)).catch(() => {
      if (requestID === errorOwner.current) setError(true);
    });
  };
  return {
    text,
    error,
    retry() {
      submit(text);
    },
    change(value: string) {
      setText(value);
      if (!composing.current) submit(value);
    },
    finishComposition() {
      if (!composing.current) return;
      composing.current = false;
      submit(text);
    },
    compositionStart() {
      composing.current = true;
    },
    compositionEnd(value: string) {
      composing.current = false;
      setText(value);
      submit(value);
    }
  };
}

export type SearchDraft = ReturnType<typeof useSearchDraft>;
