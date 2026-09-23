import eslint from "@eslint/js";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";
import globals from "globals";
import tseslint from "typescript-eslint";

export default tseslint.config(
    {
        ignores: ["dist/**", "node_modules/**"],
    },
    eslint.configs.recommended,
    ...tseslint.configs.recommended,
    {
        files: ["**/*.{ts,tsx}"],
        languageOptions: {
            globals: globals.browser,
        },
    },
    {
        files: ["**/*.tsx"],
        extends: [
            reactHooks.configs["recommended-latest"],
            reactRefresh.configs.vite,
        ],
    },
    {
        files: ["src/main.tsx"],
        rules: {
            "react-refresh/only-export-components": "off",
        },
    },
    {
        files: ["**/*.{mjs,cjs}"],
        languageOptions: {
            globals: globals.node,
        },
    },
);
