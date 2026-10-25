import { VERSION, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

// Pi 1.4.0 supplies these bare modules to extensions (docs/packages.md).
// A type-only import is erased, and Pi still exits 0 from --help, so VERSION
// has to be read. docs/cli.md prints flags from pi.registerFlag() in --help.
// Type.Object runs at load, so a broken `typebox` import fails this file too.
const marker = Type.Object({
  ok: Type.Literal("OPENSHELL_PI_EXTENSION_OK"),
});

export default function (pi: ExtensionAPI) {
  if (typeof VERSION !== "string" || VERSION.length === 0) {
    throw new Error("pi-coding-agent VERSION missing");
  }
  void marker;
  pi.registerFlag("openshell-smoke", {
    description: "OPENSHELL_PI_EXTENSION_OK",
    type: "boolean",
  });
}
