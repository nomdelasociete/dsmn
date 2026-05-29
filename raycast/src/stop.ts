import { runDsmnctlWithHUD } from "./controller";

export default async function Command() {
  await runDsmnctlWithHUD(["stop"], "dsmn stopped");
}

