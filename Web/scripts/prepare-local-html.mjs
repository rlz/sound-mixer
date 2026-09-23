import { readFileSync, writeFileSync } from "node:fs";

const indexPath = new URL("../dist/index.html", import.meta.url);
const html = readFileSync(indexPath, "utf8");
const moduleScript =
    /<script type="module" crossorigin src="(\.\/assets\/[^"]+\.js)"><\/script>/;

if (!moduleScript.test(html)) {
    throw new Error("Не найден собранный локальный скрипт Vite.");
}

// WKWebView does not execute file:// module scripts reliably; Vite emits one self-contained bundle.
writeFileSync(
    indexPath,
    html
        .replace(moduleScript, '<script defer src="$1"></script>')
        .replace(
            '<link rel="stylesheet" crossorigin',
            '<link rel="stylesheet"',
        ),
);
