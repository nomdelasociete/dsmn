import { Color, Icon, MenuBarExtra, Toast, showToast } from "@raycast/api";
import type { Image } from "@raycast/api";
import { useEffect, useState } from "react";
import { StatusReport, formatDuration, getStatus, runDsmnctlWithHUD } from "./controller";

const idleIcon: Image.ImageLike = {
  source: {
    light: "assets/menu-bar-dark.svg",
    dark: "assets/menu-bar-light.svg",
  },
};

export default function Command() {
  const [report, setReport] = useState<StatusReport | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    load();
  }, []);

  async function load() {
    try {
      setIsLoading(true);
      setReport(await getStatus());
    } catch (error) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Unable to load dsmn",
        message: error instanceof Error ? error.message : String(error),
      });
    } finally {
      setIsLoading(false);
    }
  }

  async function run(args: string[], message: string) {
    await runDsmnctlWithHUD(args, message);
    await load();
  }

  return (
    <MenuBarExtra icon={menuBarIcon(report)} isLoading={isLoading} title="" tooltip={statusTitle(report)}>
      <MenuBarExtra.Item title={statusTitle(report)} />
      {lastRequesterTitle(report) ? <MenuBarExtra.Item title={lastRequesterTitle(report) ?? ""} /> : null}
      <MenuBarExtra.Separator />
      <MenuBarExtra.Item
        title="Keep Awake 30m"
        onAction={() => run(["manual", "--minutes", "30", "--requester", "Raycast", "--context", "menu bar"], "dsmn active for 30 minutes")}
      />
      <MenuBarExtra.Item
        title="Keep Awake 90m"
        onAction={() => run(["manual", "--minutes", "90", "--requester", "Raycast", "--context", "menu bar"], "dsmn active for 90 minutes")}
      />
      <MenuBarExtra.Item title={report?.state.autoEnabled ? "Auto Off" : "Auto On"} onAction={() => run(["auto", "toggle"], "dsmn auto toggled")} />
      <MenuBarExtra.Item title="Stop" onAction={() => run(["stop"], "dsmn stopped")} />
      <MenuBarExtra.Separator />
      <MenuBarExtra.Item title="Refresh" onAction={load} />
    </MenuBarExtra>
  );
}

function menuBarIcon(report: StatusReport | null): Image.ImageLike {
  if (!report) {
    return idleIcon;
  }

  if (report.decision.shouldPreventSleep && !report.state.ownsSleepDisable) {
    return { source: Icon.Warning, tintColor: Color.Orange };
  }

  if (report.decision.shouldPreventSleep) {
    if (report.manualRemainingSeconds && report.manualRemainingSeconds > 0) {
      return { source: Icon.Stopwatch, tintColor: Color.Green };
    }

    return { source: Icon.Bolt, tintColor: Color.Green };
  }

  if (report.state.autoEnabled) {
    return { source: Icon.CircleProgress, tintColor: Color.Yellow };
  }

  return idleIcon;
}

function lastRequesterTitle(report: StatusReport | null): string | null {
  const requester = report?.state.lastRequester;
  if (!requester) {
    return null;
  }

  const text = requester.context ? `Last: ${requester.name} - ${requester.context}` : `Last: ${requester.name}`;
  return text.length <= 30 ? text : `${text.slice(0, 27)}...`;
}

function statusTitle(report: StatusReport | null): string {
  if (!report) {
    return "Loading";
  }

  if (report.decision.shouldPreventSleep && !report.state.ownsSleepDisable) {
    return "Helper required";
  }

  if (report.decision.shouldPreventSleep) {
    if (report.manualRemainingSeconds && report.manualRemainingSeconds > 0) {
      return `Active - ${formatDuration(report.manualRemainingSeconds)} left`;
    }

    return "Active - auto";
  }

  if (report.state.autoEnabled) {
    return "Auto armed";
  }

  return "Off";
}
