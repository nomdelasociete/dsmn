import { runDsmnctlWithHUD } from "./controller";

export default async function Command() {
  await runDsmnctlWithHUD(["auto", "on"], "dsmn auto on");
}

