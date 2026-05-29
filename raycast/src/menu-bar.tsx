import { MenuBarExtra, Toast, showToast } from "@raycast/api";
import { useEffect, useState } from "react";
import { StatusReport, formatDuration, getStatus, runDsmnctlWithHUD } from "./controller";

const icon = {
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
    <MenuBarExtra icon={icon} isLoading={isLoading} title="">
      <MenuBarExtra.Item title={statusTitle(report)} />
      <MenuBarExtra.Separator />
      <MenuBarExtra.Item title="Keep Awake 30m" onAction={() => run(["manual", "--minutes", "30"], "dsmn active for 30 minutes")} />
      <MenuBarExtra.Item title="Keep Awake 90m" onAction={() => run(["manual", "--minutes", "90"], "dsmn active for 90 minutes")} />
      <MenuBarExtra.Item title={report?.state.autoEnabled ? "Auto Off" : "Auto On"} onAction={() => run(["auto", "toggle"], "dsmn auto toggled")} />
      <MenuBarExtra.Item title="Stop" onAction={() => run(["stop"], "dsmn stopped")} />
      <MenuBarExtra.Separator />
      <MenuBarExtra.Item title="Refresh" onAction={load} />
    </MenuBarExtra>
  );
}

function statusTitle(report: StatusReport | null): string {
  if (!report) {
    return "Loading";
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

