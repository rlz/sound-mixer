import React, { useEffect, useState } from "react";
import {
    faSliders,
    faVolumeHigh,
    faVolumeXmark,
} from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { createRoot } from "react-dom/client";
import "./styles.css";

type OutputState = {
    uid: string;
    name: string;
    available: boolean;
    outputChannels: number;
    level: number;
    configured: boolean;
};

type MixerState = {
    schemaVersion: number;
    isEnabled: boolean;
    outputs: OutputState[];
    buses: { id: string; name: string }[];
    blackHoleRoutes: { id: string; name: string }[];
    applications: { id: string; name: string; available: boolean }[];
};

type BridgeCommand =
    | { command: "ready" }
    | { command: "setMasterEnabled"; enabled: boolean }
    | { command: "setOutputLevel"; uid: string; level: number };

declare global {
    interface Window {
        soundMixerBridge?: {
            onState: (state: MixerState) => void;
            onCommandResult: (result: {
                requestId: string;
                accepted: boolean;
                error?: string;
            }) => void;
            send: (command: BridgeCommand) => Promise<void>;
        };
    }
}

const requestCallbacks = new Map<
    string,
    (accepted: boolean, error?: string) => void
>();

window.soundMixerBridge = {
    onState: () => undefined,
    onCommandResult: ({ requestId, accepted, error }) => {
        requestCallbacks.get(requestId)?.(accepted, error);
        requestCallbacks.delete(requestId);
    },
    send: (command) =>
        new Promise((resolve, reject) => {
            const requestId = crypto.randomUUID();
            requestCallbacks.set(requestId, (accepted, error) => {
                if (accepted) resolve();
                else reject(new Error(error ?? "Native command was rejected."));
            });
            if (!window.webkit) {
                requestCallbacks.delete(requestId);
                reject(
                    new Error(
                        "The native bridge is only available in the app.",
                    ),
                );
                return;
            }
            window.webkit?.messageHandlers.soundMixer.postMessage({
                ...command,
                requestId,
            });
        }),
};

declare global {
    interface Window {
        webkit?: {
            messageHandlers: {
                soundMixer: { postMessage: (message: unknown) => void };
            };
        };
    }
}

function App() {
    const [mixerState, setMixerState] = useState<MixerState | null>(null);

    useEffect(() => {
        if (window.soundMixerBridge) {
            window.soundMixerBridge.onState = setMixerState;
            void window.soundMixerBridge
                .send({ command: "ready" })
                .catch((error: Error) => {
                    console.error("Could not request the native state:", error);
                });
        }
    }, []);

    return (
        <main className="min-h-screen bg-slate-950 p-6 text-slate-100 sm:p-10">
            <section className="mx-auto w-full max-w-3xl">
                <header className="mb-10 flex items-center gap-3">
                    <div
                        aria-hidden="true"
                        className="flex h-10 w-10 items-center justify-center rounded-xl bg-sky-400 text-slate-950"
                    >
                        <FontAwesomeIcon icon={faSliders} />
                    </div>
                    <span className="text-sm font-semibold uppercase tracking-[0.18em] text-sky-300">
                        Sound Mixer
                    </span>
                </header>

                <div className="mb-6 flex items-end justify-between gap-4">
                    <div>
                        <h1 className="text-3xl font-semibold tracking-tight">
                            Output Devices
                        </h1>
                        <p className="mt-2 text-sm text-slate-400">
                            Core Audio outputs detected by this Mac
                        </p>
                    </div>
                    <span className="rounded-full border border-slate-700 px-3 py-1 text-xs text-slate-300">
                        {mixerState
                            ? `${mixerState.outputs.length} devices`
                            : "Connecting…"}
                    </span>
                </div>

                {!mixerState ? (
                    <div
                        role="status"
                        className="rounded-2xl border border-slate-800 bg-slate-900 p-6 text-sm text-slate-400"
                    >
                        Waiting for the native device snapshot…
                    </div>
                ) : mixerState.outputs.length === 0 ? (
                    <div className="rounded-2xl border border-slate-800 bg-slate-900 p-6 text-sm text-slate-300">
                        No output devices were reported by Core Audio.
                    </div>
                ) : (
                    <ul
                        className="space-y-3"
                        aria-label="Core Audio output devices"
                    >
                        {mixerState.outputs.map((output) => (
                            <li
                                key={output.uid}
                                className="flex items-center gap-4 rounded-2xl border border-slate-800 bg-slate-900 px-5 py-4"
                            >
                                <span
                                    aria-hidden="true"
                                    className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-xl ${output.available ? "bg-emerald-400/10 text-emerald-300" : "bg-amber-400/10 text-amber-300"}`}
                                >
                                    <FontAwesomeIcon
                                        icon={
                                            output.available
                                                ? faVolumeHigh
                                                : faVolumeXmark
                                        }
                                    />
                                </span>
                                <div className="min-w-0 flex-1">
                                    <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
                                        <h2 className="font-medium text-slate-100">
                                            {output.name}
                                        </h2>
                                        <span
                                            className={`text-xs ${output.available ? "text-emerald-300" : "text-amber-300"}`}
                                        >
                                            {output.available
                                                ? "Available"
                                                : "Disconnected"}
                                        </span>
                                    </div>
                                    <p
                                        className="mt-1 truncate font-mono text-xs text-slate-500"
                                        title={output.uid}
                                    >
                                        {output.uid}
                                    </p>
                                </div>
                                <span className="shrink-0 text-right text-xs text-slate-400">
                                    {output.outputChannels}{" "}
                                    {output.outputChannels === 1
                                        ? "channel"
                                        : "channels"}
                                </span>
                            </li>
                        ))}
                    </ul>
                )}

                {mixerState && (
                    <section
                        className="mt-10"
                        aria-labelledby="applications-title"
                    >
                        <div className="mb-4">
                            <h2
                                id="applications-title"
                                className="text-xl font-semibold tracking-tight"
                            >
                                Applications
                            </h2>
                            <p className="mt-1 text-sm text-slate-400">
                                Apps currently known to Core Audio
                            </p>
                        </div>
                        {mixerState.applications.length === 0 ? (
                            <p className="rounded-2xl border border-slate-800 bg-slate-900 p-5 text-sm text-slate-400">
                                No audio applications were reported.
                            </p>
                        ) : (
                            <ul
                                className="space-y-2"
                                aria-label="Audio applications"
                            >
                                {mixerState.applications.map((application) => (
                                    <li
                                        key={application.id}
                                        className="flex justify-between rounded-xl border border-slate-800 bg-slate-900 px-5 py-3"
                                    >
                                        <span>{application.name}</span>
                                        <span
                                            className={
                                                application.available
                                                    ? "text-emerald-300"
                                                    : "text-slate-400"
                                            }
                                        >
                                            {application.available
                                                ? "Audio output detected"
                                                : "No active output"}
                                        </span>
                                    </li>
                                ))}
                            </ul>
                        )}
                    </section>
                )}

                <p className="mt-6 text-xs text-slate-500">
                    Discovery only · source capture and routing controls are not
                    connected yet
                </p>
            </section>
        </main>
    );
}

createRoot(document.getElementById("root")!).render(
    <React.StrictMode>
        <App />
    </React.StrictMode>,
);
