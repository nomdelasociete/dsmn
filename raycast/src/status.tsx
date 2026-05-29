import { Action, ActionPanel, Detail, Toast, showToast } from "@raycast/api";
import { useEffect, useState } from "react";
import { getStatus, renderStatusMarkdown } from "./controller";

export default function Command() {
  const [markdown, setMarkdown] = useState("Loading dsmn status...");

  useEffect(() => {
    load();
  }, []);

  async function load() {
    try {
      setMarkdown(renderStatusMarkdown(await getStatus()));
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setMarkdown(`# dsmn\n\n${message}`);
      await showToast({ style: Toast.Style.Failure, title: "Unable to load dsmn status", message });
    }
  }

  return (
    <Detail
      markdown={markdown}
      actions={
        <ActionPanel>
          <Action title="Refresh" onAction={load} />
        </ActionPanel>
      }
    />
  );
}

