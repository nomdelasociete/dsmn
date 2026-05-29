import { Toast, getPreferenceValues, showHUD, showToast } from "@raycast/api";
import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";

type Preferences = {
  dsmnctlPath?: string;
  defaultMinutes?: string;
};

export type StatusReport = {
  generatedAt: string;
  state: {
    autoEnabled: boolean;
    manualUntil?: string;
    ownsSleepDisable: boolean;
    lastActivationReason?: string;
    lastStopReason?: string;
    lastRequester?: {
      name: string;
      context?: string;
      event?: string;
      requestedAt: string;
    };
  };
  snapshot?: {
    powerSource: "ac" | "battery" | "unknown";
    batteryPercent?: number;
    defaultRouteAvailable?: boolean;
    lidClosed?: boolean;
  };
  agents: Array<{
    pid: number;
    executable: string;
    command: string;
    kind: "claudeCode" | "codex" | "grokBuild" | "pi";
  }>;
  decision: {
    shouldPreventSleep: boolean;
    reasons: string[];
    safetyBlocks: string[];
    stopReason?: string;
  };
  manualRemainingSeconds?: number;
};

export function defaultMinutes(): number {
  const preferences = getPreferenceValues<Preferences>();
  const parsed = Number(preferences.defaultMinutes || "90");
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 90;
}

export async function runDsmnctl(args: string[]): Promise<string> {
  const { checkedPaths, executable } = resolveDsmnctlPath();

  if (!executable) {
    throw new Error(`dsmnctl not found. Checked: ${checkedPaths.join(", ")}. Install dsmn.app or set the Raycast preference.`);
  }

  return new Promise((resolve, reject) => {
    execFile(executable, args, { timeout: 10_000 }, (error, stdout, stderr) => {
      if (error) {
        reject(new Error(String(stderr || error.message)));
        return;
      }

      resolve(String(stdout).trim());
    });
  });
}

export async function runDsmnctlWithHUD(args: string[], message: string) {
  try {
    await runDsmnctl(args);
    await showHUD(message);
  } catch (error) {
    await showToast({
      style: Toast.Style.Failure,
      title: "dsmn failed",
      message: error instanceof Error ? error.message : String(error),
    });
    throw error;
  }
}

export async function getStatus(): Promise<StatusReport> {
  const output = await runDsmnctl(["status", "--json"]);
  return JSON.parse(output) as StatusReport;
}

export function renderStatusMarkdown(report: StatusReport): string {
  const lines = [
    `# dsmn`,
    ``,
    `**Status:** ${report.decision.shouldPreventSleep ? "active" : "inactive"}`,
    `**Auto:** ${report.state.autoEnabled ? "on" : "off"}`,
    `**Manual:** ${formatManual(report)}`,
    `**Last request:** ${formatLastRequester(report)}`,
    `**Power:** ${formatPower(report)}`,
    `**Agents:** ${report.agents.length}`,
  ];

  if (report.agents.length > 0) {
    lines.push(``, `## Agents`);
    for (const agent of report.agents) {
      lines.push(`- ${agentDisplayName(agent.kind)} \`${agent.pid}\``);
    }
  }

  if (report.decision.reasons.length > 0) {
    lines.push(``, `## Reasons`, report.decision.reasons.map((reason) => `- ${reason}`).join("\n"));
  }

  if (report.decision.safetyBlocks.length > 0) {
    lines.push(``, `## Safety Blocks`, report.decision.safetyBlocks.map((reason) => `- ${reason}`).join("\n"));
  }

  if (report.decision.stopReason) {
    lines.push(``, `**Stop reason:** ${report.decision.stopReason}`);
  }

  return lines.join("\n");
}

export function formatDuration(seconds: number): string {
  if (seconds <= 0) {
    return "0m";
  }

  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) {
    return `${minutes}m`;
  }

  const hours = Math.floor(minutes / 60);
  const leftoverMinutes = minutes % 60;
  return leftoverMinutes === 0 ? `${hours}h` : `${hours}h ${leftoverMinutes}m`;
}

function resolveDsmnctlPath(): { checkedPaths: string[]; executable?: string } {
  const preferences = getPreferenceValues<Preferences>();
  if (preferences.dsmnctlPath && preferences.dsmnctlPath.trim().length > 0) {
    const configuredPath = preferences.dsmnctlPath.trim();
    return {
      checkedPaths: [configuredPath],
      executable: existsSync(configuredPath) ? configuredPath : undefined,
    };
  }

  if (process.env.DSMNCTL_PATH) {
    return {
      checkedPaths: [process.env.DSMNCTL_PATH],
      executable: existsSync(process.env.DSMNCTL_PATH) ? process.env.DSMNCTL_PATH : undefined,
    };
  }

  const checkedPaths = [
    "/Applications/dsmn.app/Contents/Library/Helpers/dsmnctl",
    path.join(homedir(), "Applications/dsmn.app/Contents/Library/Helpers/dsmnctl"),
    path.resolve(process.cwd(), "../.build/debug/dsmnctl"),
    path.resolve(process.cwd(), "../DerivedData/Build/Products/Debug/dsmn.app/Contents/Library/Helpers/dsmnctl"),
  ];

  return {
    checkedPaths,
    executable: checkedPaths.find((candidate) => existsSync(candidate)),
  };
}

function formatManual(report: StatusReport): string {
  if (!report.manualRemainingSeconds || report.manualRemainingSeconds <= 0) {
    return "off";
  }

  return `${formatDuration(report.manualRemainingSeconds)} remaining`;
}

function formatLastRequester(report: StatusReport): string {
  const requester = report.state.lastRequester;
  if (!requester) {
    return "unknown";
  }

  return requester.context ? `${requester.name} - ${requester.context}` : requester.name;
}

function formatPower(report: StatusReport): string {
  if (!report.snapshot) {
    return "unknown";
  }

  const parts: string[] = [report.snapshot.powerSource];
  if (typeof report.snapshot.batteryPercent === "number") {
    parts.push(`${report.snapshot.batteryPercent}%`);
  }
  if (typeof report.snapshot.defaultRouteAvailable === "boolean") {
    parts.push(report.snapshot.defaultRouteAvailable ? "network" : "no network");
  }
  if (typeof report.snapshot.lidClosed === "boolean") {
    parts.push(report.snapshot.lidClosed ? "lid closed" : "lid open");
  }

  return parts.join(" - ");
}

function agentDisplayName(kind: StatusReport["agents"][number]["kind"]): string {
  switch (kind) {
    case "claudeCode":
      return "Claude Code";
    case "codex":
      return "Codex";
    case "grokBuild":
      return "Grok Build";
    case "pi":
      return "Pi";
  }
}
