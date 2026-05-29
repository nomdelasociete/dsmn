import { Action, ActionPanel, Form } from "@raycast/api";
import { useState } from "react";
import { defaultMinutes, runDsmnctlWithHUD } from "./controller";

type Values = {
  preset: string;
  customMinutes?: string;
};

export default function Command() {
  const initialMinutes = String(defaultMinutes());
  const [preset, setPreset] = useState(initialMinutes);

  async function submit(values: Values) {
    const minutes = parseMinutes(values);
    await runDsmnctlWithHUD(["manual", "--minutes", String(minutes)], `dsmn active for ${minutes} minutes`);
  }

  return (
    <Form
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Start dsmn" onSubmit={submit} />
        </ActionPanel>
      }
    >
      <Form.Dropdown id="preset" title="Duration" value={preset} onChange={setPreset}>
        <Form.Dropdown.Item title="15 minutes" value="15" />
        <Form.Dropdown.Item title="30 minutes" value="30" />
        <Form.Dropdown.Item title="60 minutes" value="60" />
        <Form.Dropdown.Item title="90 minutes" value="90" />
        <Form.Dropdown.Item title="2 hours" value="120" />
        <Form.Dropdown.Item title="Custom" value="custom" />
      </Form.Dropdown>
      {preset === "custom" ? <Form.TextField id="customMinutes" title="Minutes" placeholder="90" /> : null}
    </Form>
  );
}

function parseMinutes(values: Values): number {
  const raw = values.preset === "custom" ? values.customMinutes : values.preset;
  const minutes = Number(raw);

  if (!Number.isFinite(minutes) || minutes <= 0) {
    throw new Error("Enter a positive duration in minutes.");
  }

  return Math.floor(minutes);
}

