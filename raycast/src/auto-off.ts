import { runDsmnctlWithHUD } from "./controller";

export default async function Command() {
  await runDsmnctlWithHUD(["auto", "off"], "dsmn auto off");
}

