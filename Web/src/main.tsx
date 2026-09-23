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
    isBlackHole: boolean;
    available: boolean;
    outputChannels: number;
    level: number;
    configured: boolean;
    routeError?: string | null;
};

type DeviceState = {
    uid: string;
    name: string;
    available: boolean;
    outputChannels: number;
};

type MixerState = {
    schemaVersion: number;
    isEnabled: boolean;
    devices: DeviceState[];
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
    const [selectedItem, setSelectedItem] = useState<string | null>(null);
    const [pending, setPending] = useState<string | null>(null);
    const [commandError, setCommandError] = useState<string | null>(null);

    const send = async (
        key: string,
        command: BridgeCommand,
        rollback?: () => void,
    ) => {
        if (!window.soundMixerBridge || pending) return;
        setPending(key);
        setCommandError(null);
        try {
            await window.soundMixerBridge.send(command);
        } catch (error) {
            rollback?.();
            setCommandError(
                error instanceof Error
                    ? error.message
                    : "The change could not be saved.",
            );
        } finally {
            setPending(null);
        }
    };

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
            <section className="mx-auto w-full max-w-5xl">
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

                <section className="mb-8 flex flex-wrap items-center justify-between gap-4 rounded-2xl border border-slate-800 bg-slate-900 px-5 py-4">
                    <div>
                        <h1 className="font-semibold">Mixing On/Off</h1>
                        <p
                            className="mt-1 text-sm text-slate-400"
                            role="status"
                        >
                            {mixerState?.isEnabled
                                ? "Sound Mixer is outputting audio."
                                : "Sound Mixer is not currently outputting audio."}
                        </p>
                    </div>
                    <button
                        type="button"
                        role="switch"
                        aria-checked={mixerState?.isEnabled ?? false}
                        aria-label="Mixing On/Off"
                        disabled={!mixerState || pending !== null}
                        onClick={() =>
                            mixerState &&
                            void send("master", {
                                command: "setMasterEnabled",
                                enabled: !mixerState.isEnabled,
                            })
                        }
                        className={`rounded-full px-4 py-2 text-sm font-semibold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sky-300 disabled:opacity-50 ${mixerState?.isEnabled ? "bg-emerald-300 text-slate-950" : "bg-slate-700 text-slate-100"}`}
                    >
                        {mixerState?.isEnabled ? "On" : "Off"}
                    </button>
                </section>

                {commandError && (
                    <p
                        className="mb-5 rounded-xl border border-rose-800 bg-rose-950/50 p-3 text-sm text-rose-200"
                        role="alert"
                    >
                        {commandError}
                    </p>
                )}

                <div className="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)]">
                    <nav aria-label="Mixer items" className="space-y-5">
                        <ItemGroup title="Output Devices">
                            {mixerState?.outputs
                                .filter((output) => !output.isBlackHole)
                                .map((output) => (
                                    <button
                                        key={output.uid}
                                        type="button"
                                        aria-current={
                                            selectedItem ===
                                            `output:${output.uid}`
                                                ? "true"
                                                : undefined
                                        }
                                        onClick={() =>
                                            setSelectedItem(
                                                `output:${output.uid}`,
                                            )
                                        }
                                        className={`flex w-full items-center justify-between gap-3 rounded-lg px-3 py-2 text-left text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 ${selectedItem === `output:${output.uid}` ? "bg-sky-400/15 text-sky-100 ring-1 ring-sky-300" : "text-slate-300 hover:bg-slate-800"}`}
                                    >
                                        <span className="min-w-0 truncate">
                                            {output.name}
                                        </span>
                                        <span
                                            className={
                                                output.available
                                                    ? "text-emerald-300"
                                                    : "text-amber-300"
                                            }
                                        >
                                            {output.available
                                                ? "Available"
                                                : "Disconnected"}
                                        </span>
                                    </button>
                                ))}
                            {mixerState?.outputs.every(
                                (output) => output.isBlackHole,
                            ) && (
                                <p className="px-3 text-sm text-slate-500">
                                    No output devices.
                                </p>
                            )}
                        </ItemGroup>
                        <ItemGroup title="Virtual Buses">
                            {mixerState?.buses.map((bus) => (
                                <button
                                    key={bus.id}
                                    type="button"
                                    aria-current={
                                        selectedItem === `bus:${bus.id}`
                                            ? "true"
                                            : undefined
                                    }
                                    onClick={() =>
                                        setSelectedItem(`bus:${bus.id}`)
                                    }
                                    className={`w-full rounded-lg px-3 py-2 text-left text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 ${selectedItem === `bus:${bus.id}` ? "bg-sky-400/15 text-sky-100 ring-1 ring-sky-300" : "text-slate-300 hover:bg-slate-800"}`}
                                >
                                    {bus.name}
                                </button>
                            ))}
                            {mixerState?.buses.length === 0 && (
                                <p className="px-3 text-sm text-slate-500">
                                    No virtual buses.
                                </p>
                            )}
                        </ItemGroup>
                        <ItemGroup title="BlackHole Routes">
                            {mixerState?.blackHoleRoutes.map((route) => (
                                <button
                                    key={route.id}
                                    type="button"
                                    aria-current={
                                        selectedItem === `blackHole:${route.id}`
                                            ? "true"
                                            : undefined
                                    }
                                    onClick={() =>
                                        setSelectedItem(`blackHole:${route.id}`)
                                    }
                                    className={`w-full rounded-lg px-3 py-2 text-left text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 ${selectedItem === `blackHole:${route.id}` ? "bg-sky-400/15 text-sky-100 ring-1 ring-sky-300" : "text-slate-300 hover:bg-slate-800"}`}
                                >
                                    {route.name}
                                </button>
                            ))}
                            {mixerState?.blackHoleRoutes.length === 0 && (
                                <p className="px-3 text-sm text-slate-500">
                                    No BlackHole routes.
                                </p>
                            )}
                        </ItemGroup>
                    </nav>
                    <div>
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
                                    ? `${mixerState.outputs.filter((output) => !output.isBlackHole).length} devices`
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
                        ) : mixerState.outputs.every(
                              (output) => output.isBlackHole,
                          ) ? (
                            <div className="rounded-2xl border border-slate-800 bg-slate-900 p-6 text-sm text-slate-300">
                                No output devices were reported by Core Audio.
                            </div>
                        ) : (
                            <ul
                                className="space-y-3"
                                aria-label="Core Audio output devices"
                            >
                                {mixerState.outputs
                                    .filter((output) => !output.isBlackHole)
                                    .map((output) => (
                                        <li
                                            key={output.uid}
                                            className={`flex flex-wrap items-center gap-4 rounded-2xl border bg-slate-900 px-5 py-4 ${selectedItem === `output:${output.uid}` ? "border-sky-300" : "border-slate-800"}`}
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
                                                {output.routeError && (
                                                    <p
                                                        className="mt-2 text-sm text-rose-300"
                                                        role="status"
                                                    >
                                                        Route unavailable:{" "}
                                                        {output.routeError}
                                                    </p>
                                                )}
                                            </div>
                                            <span className="shrink-0 text-right text-xs text-slate-400">
                                                {output.outputChannels}{" "}
                                                {output.outputChannels === 1
                                                    ? "channel"
                                                    : "channels"}
                                            </span>
                                            {output.configured && (
                                                <label className="flex min-w-48 flex-1 items-center gap-3 text-xs text-slate-300">
                                                    <span>Master level</span>
                                                    <input
                                                        type="range"
                                                        min="0"
                                                        max="1"
                                                        step="0.01"
                                                        value={output.level}
                                                        aria-label={`${output.name} master level`}
                                                        aria-valuetext={`${Math.round(output.level * 100)} percent`}
                                                        disabled={
                                                            pending !== null
                                                        }
                                                        onChange={(event) => {
                                                            const level =
                                                                Number(
                                                                    event
                                                                        .currentTarget
                                                                        .value,
                                                                );
                                                            setMixerState(
                                                                (current) =>
                                                                    current && {
                                                                        ...current,
                                                                        outputs:
                                                                            current.outputs.map(
                                                                                (
                                                                                    item,
                                                                                ) =>
                                                                                    item.uid ===
                                                                                    output.uid
                                                                                        ? {
                                                                                              ...item,
                                                                                              level,
                                                                                          }
                                                                                        : item,
                                                                            ),
                                                                    },
                                                            );
                                                        }}
                                                        onPointerUp={(
                                                            event,
                                                        ) => {
                                                            void send(
                                                                `output:${output.uid}`,
                                                                {
                                                                    command:
                                                                        "setOutputLevel",
                                                                    uid: output.uid,
                                                                    level: Number(
                                                                        event
                                                                            .currentTarget
                                                                            .value,
                                                                    ),
                                                                },
                                                                () => {
                                                                    setMixerState(
                                                                        (
                                                                            current,
                                                                        ) =>
                                                                            current && {
                                                                                ...current,
                                                                                outputs:
                                                                                    current.outputs.map(
                                                                                        (
                                                                                            item,
                                                                                        ) =>
                                                                                            item.uid ===
                                                                                            output.uid
                                                                                                ? {
                                                                                                      ...item,
                                                                                                      level: output.level,
                                                                                                  }
                                                                                                : item,
                                                                                    ),
                                                                            },
                                                                    );
                                                                },
                                                            );
                                                        }}
                                                        onKeyUp={(event) => {
                                                            if (
                                                                event.key.startsWith(
                                                                    "Arrow",
                                                                )
                                                            ) {
                                                                void send(
                                                                    `output:${output.uid}`,
                                                                    {
                                                                        command:
                                                                            "setOutputLevel",
                                                                        uid: output.uid,
                                                                        level: Number(
                                                                            event
                                                                                .currentTarget
                                                                                .value,
                                                                        ),
                                                                    },
                                                                    () => {
                                                                        setMixerState(
                                                                            (
                                                                                current,
                                                                            ) =>
                                                                                current && {
                                                                                    ...current,
                                                                                    outputs:
                                                                                        current.outputs.map(
                                                                                            (
                                                                                                item,
                                                                                            ) =>
                                                                                                item.uid ===
                                                                                                output.uid
                                                                                                    ? {
                                                                                                          ...item,
                                                                                                          level: output.level,
                                                                                                      }
                                                                                                    : item,
                                                                                        ),
                                                                                },
                                                                        );
                                                                    },
                                                                );
                                                            }
                                                        }}
                                                    />
                                                    <span className="w-9 text-right tabular-nums">
                                                        {Math.round(
                                                            output.level * 100,
                                                        )}
                                                        %
                                                    </span>
                                                </label>
                                            )}
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
                                        {mixerState.applications.map(
                                            (application) => (
                                                <li
                                                    key={application.id}
                                                    className="flex justify-between rounded-xl border border-slate-800 bg-slate-900 px-5 py-3"
                                                >
                                                    <span>
                                                        {application.name}
                                                    </span>
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
                                            ),
                                        )}
                                    </ul>
                                )}
                            </section>
                        )}

                        <p className="mt-6 text-xs text-slate-500">
                            Output levels are available for configured mixes.
                            Source capture and routing controls are still in
                            development.
                        </p>
                    </div>
                </div>
            </section>
        </main>
    );
}

function ItemGroup({
    title,
    children,
}: {
    title: string;
    children: React.ReactNode;
}) {
    return (
        <section
            aria-label={title}
            className="rounded-xl border border-slate-800 bg-slate-900 p-3"
        >
            <h2 className="mb-2 px-3 text-xs font-semibold uppercase tracking-wider text-slate-400">
                {title}
            </h2>
            <div className="space-y-1">{children}</div>
        </section>
    );
}

createRoot(document.getElementById("root")!).render(
    <React.StrictMode>
        <App />
    </React.StrictMode>,
);
