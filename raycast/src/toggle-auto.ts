import { runDsmnctlWithHUD } from "./controller";

export default async function Command() {
  await runDsmnctlWithHUD(["auto", "toggle"], "dsmn auto toggled");
}

