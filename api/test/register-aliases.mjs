// Lets `node --test` resolve the "@/..." imports the API uses (tsconfig `paths`), so tests can import
// any module, not only ones written with relative imports.
import { registerHooks } from "node:module";

const SRC = new URL("../src/", import.meta.url);

registerHooks({
  resolve(specifier, context, next) {
    if (specifier.startsWith("@/")) return next(new URL(`${specifier.slice(2)}.ts`, SRC).href, context);
    return next(specifier, context);
  },
});
