import React from "react";
import { createRoot } from "react-dom/client";
import "./styles.css";

function App() {
    return (
        <main className="flex min-h-screen items-center justify-center bg-slate-950 p-8 text-slate-100">
            <section className="w-full max-w-2xl rounded-2xl border border-slate-700 bg-slate-900 p-10 shadow-2xl">
                <div className="mb-8 flex items-center gap-3">
                    <div aria-hidden="true" className="flex h-10 w-10 items-center justify-center rounded-xl bg-sky-400 font-bold text-slate-950">
                        S
                    </div>
                    <span className="text-sm font-semibold uppercase tracking-[0.18em] text-sky-300">Sound Mixer</span>
                </div>
                <h1 className="text-3xl font-semibold tracking-tight">Оболочка приложения готова</h1>
                <p className="mt-4 max-w-xl leading-7 text-slate-300">
                    Интерфейс React загружен из ресурсов приложения. Обнаружение устройств, маршруты и управление звуком появятся в следующих задачах.
                </p>
                <div className="mt-8 rounded-xl border border-slate-700 bg-slate-800/70 px-5 py-4 text-sm text-slate-300">
                    Локальный интерфейс · macOS 15+ · без подключения к сети
                </div>
            </section>
        </main>
    );
}

createRoot(document.getElementById("root")!).render(
    <React.StrictMode>
        <App />
    </React.StrictMode>,
);
