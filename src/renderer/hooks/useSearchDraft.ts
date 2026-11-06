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

  const lastSynchronizedQuery = useRef({
    text: snapshot.searchText,
    requestID: snapshot.searchTextRequestID
  });
  const latestSnapshot = useRef(snapshot);
  latestSnapshot.current = snapshot;
  const pending = useRef<{
    requestID: string;
    snapshotRevision?: number;
    baseText: string;
    baseRequestID?: string;
  }>(undefined);

  const synchronize = (incoming: BaselineSnapshot) => {
    if (composing.current) return;
    const requestID = incoming.searchTextRequestID;
    if (pending.current) {
      const ownAcknowledgement = requestID === pending.current.requestID;
      const afterAcknowledgement =
        pending.current.snapshotRevision !== undefined &&
        incoming.snapshotRevision !== undefined &&
        incoming.snapshotRevision >= pending.current.snapshotRevision;
      // An external snapshot may have been queued before the local edit. Do not
      // replace that edit until its own causal position in main is known. The
      // invoke revision also handles React coalescing the own echo with a later
      // external edit, so we do not wait forever for a skipped acknowledgement.
      if (!ownAcknowledgement && !afterAcknowledgement) return;
      pending.current = undefined;
    }
    if (clientID.current && requestID?.startsWith(`${clientID.current}:`)) {
      if (requestID !== `${clientID.current}:${sequence.current}`) return;
    }
    if (
      lastSynchronizedQuery.current.text === incoming.searchText &&
      lastSynchronizedQuery.current.requestID === requestID
    )
      return;
    lastSynchronizedQuery.current = { text: incoming.searchText, requestID };
    errorOwner.current = requestID;
    setText(incoming.searchText);
    setError(false);
  };

  useEffect(() => {
    synchronize(snapshot);
  }, [snapshot.searchText, snapshot.searchTextRequestID, snapshot.snapshotRevision]);

  const submit = (value: string) => {
    clientID.current ??= crypto.randomUUID();
    const requestID = `${clientID.current}:${++sequence.current}`;
    pending.current = {
      requestID,
      baseText: latestSnapshot.current.searchText,
      baseRequestID: latestSnapshot.current.searchTextRequestID
    };
    errorOwner.current = requestID;
    setError(false);
    void Promise.resolve(baseline.setSearchText(value, requestID)).then(
      (acknowledgement) => {
        if (pending.current?.requestID !== requestID || acknowledgement?.requestID !== requestID)
          return;
        pending.current.snapshotRevision = acknowledgement.snapshotRevision;
        synchronize(latestSnapshot.current);
      },
      () => {
        const failed = pending.current;
        if (failed?.requestID === requestID) {
          pending.current = undefined;
          const incoming = latestSnapshot.current;
          if (
            incoming.searchTextRequestID !== failed.baseRequestID ||
            incoming.searchText !== failed.baseText
          ) {
            synchronize(incoming);
          }
        }
        if (requestID === errorOwner.current) setError(true);
      }
    );
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
