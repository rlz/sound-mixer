import { useEffect } from "react";
import { faVolumeHigh, faVolumeXmark } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { useMixerStore } from "./store";
import type { BridgeCommand } from "./types";
import "./bridge";
import { ItemGroup } from "./components/ItemGroup";
import { AppHeader } from "./components/AppHeader";
import { MasterSwitch } from "./components/MasterSwitch";
import "./styles.css";

export function App() {
    const mixerState = useMixerStore((state) => state.mixerState);
    const setMixerState = useMixerStore((state) => state.setMixerState);
    const selectedItem = useMixerStore((state) => state.selectedItem);
    const setSelectedItem = useMixerStore((state) => state.setSelectedItem);
    const pending = useMixerStore((state) => state.pending);
    const setPending = useMixerStore((state) => state.setPending);
    const setCommandError = useMixerStore((state) => state.setCommandError);
    const commandError = useMixerStore((state) => state.commandError);
    const busNameDraft = useMixerStore((state) => state.busNameDraft);
    const setBusNameDraft = useMixerStore((state) => state.setBusNameDraft);
    const editingBusId = useMixerStore((state) => state.editingBusId);
    const setEditingBusId = useMixerStore((state) => state.setEditingBusId);
    const editingRouteId = useMixerStore((state) => state.editingRouteId);
    const setEditingRouteId = useMixerStore((state) => state.setEditingRouteId);

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

    const selectedOutput = mixerState?.outputs.find(
        (output) => selectedItem === `output:${output.uid}`,
    );
    const selectedBus = mixerState?.buses.find(
        (bus) => selectedItem === `bus:${bus.id}`,
    );
    const selectedRoute = mixerState?.blackHoleRoutes.find(
        (route) => selectedItem === `blackHole:${route.id}`,
    );
    const selectedTarget = selectedOutput
        ? { target: "output" as const, id: selectedOutput.uid }
        : selectedBus
          ? { target: "bus" as const, id: selectedBus.id }
          : selectedRoute
            ? { target: "route" as const, id: selectedRoute.id }
            : null;
    const selectedMix =
        selectedTarget &&
        mixerState?.mixes.find(
            (mix) =>
                mix.target === selectedTarget.target &&
                mix.id === selectedTarget.id,
        );
    const sourceChoice = useMixerStore((state) => state.sourceChoice);
    const setSourceChoice = useMixerStore((state) => state.setSourceChoice);

    useEffect(() => {
        if (window.soundMixerBridge) {
            window.soundMixerBridge.onState = setMixerState;
            void window.soundMixerBridge
                .send({ command: "ready" })
                .catch((error: Error) => {
                    console.error("Could not request the native state:", error);
                });
        }
    }, [setMixerState]);

    return (
        <main className="min-h-screen bg-slate-950 p-6 text-slate-100 sm:p-10">
            <section className="mx-auto w-full max-w-5xl">
                <AppHeader />

                <MasterSwitch
                    mixerState={mixerState}
                    pending={pending}
                    onToggle={() =>
                        mixerState &&
                        void send("master", {
                            command: "setMasterEnabled",
                            enabled: !mixerState.isEnabled,
                        })
                    }
                />

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
                                        onClick={() => {
                                            setSelectedItem(
                                                `output:${output.uid}`,
                                            );
                                            setBusNameDraft(null);
                                            setEditingBusId(null);
                                            setEditingRouteId(null);
                                        }}
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
                            <button
                                type="button"
                                disabled={pending !== null}
                                onClick={() => {
                                    setEditingBusId(null);
                                    setEditingRouteId(null);
                                    setSelectedItem("bus:new");
                                    setBusNameDraft("New Bus");
                                }}
                                className="w-full rounded-lg px-3 py-2 text-left text-sm text-sky-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:opacity-50"
                            >
                                + Add virtual bus
                            </button>
                            {mixerState?.buses.map((bus) => (
                                <button
                                    key={bus.id}
                                    type="button"
                                    aria-current={
                                        selectedItem === `bus:${bus.id}`
                                            ? "true"
                                            : undefined
                                    }
                                    onClick={() => {
                                        setSelectedItem(`bus:${bus.id}`);
                                        setBusNameDraft(bus.name);
                                        setEditingBusId(bus.id);
                                        setEditingRouteId(null);
                                    }}
                                    className={`w-full rounded-lg px-3 py-2 text-left text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 ${selectedItem === `bus:${bus.id}` ? "bg-sky-400/15 text-sky-100 ring-1 ring-sky-300" : "text-slate-300 hover:bg-slate-800"}`}
                                >
                                    {bus.name}
                                </button>
                            ))}
                            {mixerState?.buses.map(
                                (bus) =>
                                    selectedItem === `bus:${bus.id}` && (
                                        <div
                                            key={`${bus.id}:actions`}
                                            className="flex gap-2 px-2 pb-2"
                                        >
                                            <button
                                                type="button"
                                                disabled={pending !== null}
                                                className="text-xs text-rose-300 underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300"
                                                onClick={() => {
                                                    if (
                                                        window.confirm(
                                                            `Delete “${bus.name}”? Mixes that use this bus will prevent deletion.`,
                                                        )
                                                    ) {
                                                        void send(
                                                            `bus-delete:${bus.id}`,
                                                            {
                                                                command:
                                                                    "deleteBus",
                                                                id: bus.id,
                                                            },
                                                        );
                                                    }
                                                }}
                                            >
                                                Delete
                                            </button>
                                        </div>
                                    ),
                            )}
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
                                    onClick={() => {
                                        setSelectedItem(
                                            `blackHole:${route.id}`,
                                        );
                                        setBusNameDraft(route.name);
                                        setEditingRouteId(route.id);
                                        setEditingBusId(null);
                                    }}
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
                                    {selectedOutput?.name ??
                                        selectedBus?.name ??
                                        selectedRoute?.name ??
                                        "Settings"}
                                </h1>
                                <p className="mt-2 text-sm text-slate-400">
                                    {selectedOutput
                                        ? "Output device settings"
                                        : selectedBus
                                          ? "Virtual bus settings"
                                          : selectedRoute
                                            ? "BlackHole route settings"
                                            : "Select an output or virtual item to view its settings."}
                                </p>
                            </div>
                            <span className="rounded-full border border-slate-700 px-3 py-1 text-xs text-slate-300">
                                {selectedOutput
                                    ? `${selectedOutput.outputChannels} channels`
                                    : selectedRoute
                                      ? `Device ${selectedRoute.deviceUID}`
                                      : "Sound Mixer"}
                            </span>
                        </div>

                        {(selectedBus ||
                            selectedRoute ||
                            selectedItem === "bus:new") && (
                            <section
                                className="mb-5 rounded-2xl border border-slate-800 bg-slate-900 p-5"
                                aria-label="Virtual item settings"
                            >
                                <form
                                    className="space-y-3"
                                    onSubmit={(event) => {
                                        event.preventDefault();
                                        if (editingRouteId) {
                                            void send("route-rename", {
                                                command: "renameRoute",
                                                id: editingRouteId,
                                                name: busNameDraft ?? "",
                                            });
                                        } else if (editingBusId) {
                                            void send("bus-rename", {
                                                command: "renameBus",
                                                id: editingBusId,
                                                name: busNameDraft ?? "",
                                            });
                                        } else {
                                            void send("bus-create", {
                                                command: "createBus",
                                                name: busNameDraft ?? "",
                                            });
                                        }
                                    }}
                                >
                                    <label
                                        htmlFor="selected-virtual-name"
                                        className="block text-sm font-medium text-slate-200"
                                    >
                                        {selectedRoute
                                            ? "Route name"
                                            : "Virtual bus name"}
                                    </label>
                                    <input
                                        id="selected-virtual-name"
                                        maxLength={64}
                                        required
                                        value={
                                            busNameDraft ??
                                            selectedBus?.name ??
                                            selectedRoute?.name ??
                                            ""
                                        }
                                        onChange={(event) =>
                                            setBusNameDraft(
                                                event.currentTarget.value,
                                            )
                                        }
                                        className="w-full rounded-lg border border-slate-600 bg-slate-950 px-3 py-2 text-sm text-slate-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300"
                                    />
                                    {selectedRoute && (
                                        <p className="font-mono text-xs text-slate-500">
                                            Core Audio UID:{" "}
                                            {selectedRoute.deviceUID}
                                        </p>
                                    )}
                                    <button
                                        type="submit"
                                        disabled={pending !== null}
                                        className="rounded-lg bg-sky-300 px-3 py-2 text-sm font-semibold text-slate-950 disabled:opacity-50"
                                    >
                                        Save name
                                    </button>
                                </form>
                            </section>
                        )}

                        {selectedMix && selectedTarget && (
                            <section
                                className="mb-5 rounded-2xl border border-slate-800 bg-slate-900 p-5"
                                aria-label="Mix sources"
                            >
                                <div className="mb-4 flex flex-wrap items-end gap-3">
                                    <label className="min-w-56 flex-1 text-sm">
                                        Add a source
                                        <select
                                            value={sourceChoice}
                                            onChange={(event) =>
                                                setSourceChoice(
                                                    event.currentTarget.value,
                                                )
                                            }
                                            className="mt-1 w-full rounded-lg border border-slate-600 bg-slate-950 px-3 py-2 text-slate-100"
                                        >
                                            <option value="">
                                                Choose an available source
                                            </option>
                                            {mixerState?.devices
                                                .filter(
                                                    (device) =>
                                                        device.inputChannels >
                                                            0 &&
                                                        device.available,
                                                )
                                                .map((device) => (
                                                    <option
                                                        key={`input:${device.uid}`}
                                                        value={`inputDevice|${device.uid}`}
                                                    >
                                                        {device.name} · input
                                                    </option>
                                                ))}
                                            {mixerState?.applications
                                                .filter((app) => app.available)
                                                .map((app) => (
                                                    <option
                                                        key={`application:${app.id}`}
                                                        value={`application|${app.id}`}
                                                    >
                                                        {app.name} · application
                                                    </option>
                                                ))}
                                            {mixerState?.buses
                                                .filter(
                                                    (bus) =>
                                                        !(
                                                            selectedTarget.target ===
                                                                "bus" &&
                                                            bus.id ===
                                                                selectedTarget.id
                                                        ),
                                                )
                                                .map((bus) => (
                                                    <option
                                                        key={`bus:${bus.id}`}
                                                        value={`bus|${bus.id}`}
                                                    >
                                                        {bus.name} · bus
                                                    </option>
                                                ))}
                                        </select>
                                    </label>
                                    <button
                                        type="button"
                                        disabled={
                                            !sourceChoice || pending !== null
                                        }
                                        className="rounded-lg bg-sky-300 px-3 py-2 text-sm font-semibold text-slate-950 disabled:opacity-50"
                                        onClick={() => {
                                            if (!sourceChoice) return;
                                            const [kind, sourceID] =
                                                sourceChoice.split("|");
                                            void send(`mix-add:${sourceID}`, {
                                                command: "addMixInput",
                                                ...selectedTarget,
                                                kind,
                                                sourceID,
                                                monoPlacement: "both",
                                            });
                                            setSourceChoice("");
                                        }}
                                    >
                                        Add source
                                    </button>
                                </div>
                                {selectedMix.inputs.length === 0 ? (
                                    <p className="text-sm text-slate-400">
                                        This mix is empty. Choose an input,
                                        active application, or virtual bus
                                        above.
                                    </p>
                                ) : (
                                    <ul className="space-y-3">
                                        {selectedMix.inputs.map((input) => {
                                            const name =
                                                input.kind === "inputDevice"
                                                    ? (mixerState?.devices.find(
                                                          (device) =>
                                                              device.uid ===
                                                              input.id,
                                                      )?.name ?? input.id)
                                                    : input.kind ===
                                                        "application"
                                                      ? (mixerState?.applications.find(
                                                            (app) =>
                                                                app.id ===
                                                                input.id,
                                                        )?.name ?? input.id)
                                                      : (mixerState?.buses.find(
                                                            (bus) =>
                                                                bus.id ===
                                                                input.id,
                                                        )?.name ?? input.id);
                                            const available =
                                                input.kind === "inputDevice"
                                                    ? mixerState?.devices.some(
                                                          (device) =>
                                                              device.uid ===
                                                                  input.id &&
                                                              device.available,
                                                      )
                                                    : input.kind ===
                                                        "application"
                                                      ? mixerState?.applications.some(
                                                            (app) =>
                                                                app.id ===
                                                                    input.id &&
                                                                app.available,
                                                        )
                                                      : true;
                                            const captureState =
                                                input.kind === "inputDevice"
                                                    ? (mixerState?.inputCaptureStates.find(
                                                          (state) =>
                                                              state.uid ===
                                                              input.id,
                                                      )?.state ?? "stopped")
                                                    : input.kind ===
                                                        "application"
                                                      ? (mixerState?.applications.find(
                                                            (app) =>
                                                                app.id ===
                                                                input.id,
                                                        )?.captureState ??
                                                        "stopped")
                                                      : "capturing";
                                            const unavailableReason = !available
                                                ? input.kind === "inputDevice"
                                                    ? "Device disconnected."
                                                    : input.kind ===
                                                        "application"
                                                      ? "Application is not producing audio."
                                                      : "Source unavailable."
                                                : captureState ===
                                                    "permissionDenied"
                                                  ? "Permission denied. Allow access in System Settings."
                                                  : captureState.startsWith(
                                                          "unavailable:",
                                                      )
                                                    ? captureState
                                                          .slice(
                                                              "unavailable:"
                                                                  .length,
                                                          )
                                                          .trim()
                                                    : null;
                                            return (
                                                <li
                                                    key={`${input.kind}:${input.id}`}
                                                    className="rounded-xl border border-slate-800 p-3"
                                                >
                                                    <div className="mb-2 flex items-center justify-between gap-3">
                                                        <div className="min-w-0">
                                                            <span className="block truncate text-sm">
                                                                {name}
                                                            </span>
                                                            <span
                                                                className={`text-xs ${available ? "text-emerald-300" : "text-amber-300"}`}
                                                            >
                                                                {available
                                                                    ? captureState ===
                                                                      "capturing"
                                                                        ? "Capturing"
                                                                        : "Available"
                                                                    : "Unavailable"}
                                                            </span>
                                                            {unavailableReason && (
                                                                <span
                                                                    className="mt-1 block text-xs text-amber-200"
                                                                    role="status"
                                                                >
                                                                    {
                                                                        unavailableReason
                                                                    }
                                                                    {captureState ===
                                                                        "permissionDenied" && (
                                                                        <button
                                                                            type="button"
                                                                            className="ml-1 underline"
                                                                            onClick={() =>
                                                                                void send(
                                                                                    `privacy:${input.id}`,
                                                                                    {
                                                                                        command:
                                                                                            "openPrivacySettings",
                                                                                    },
                                                                                )
                                                                            }
                                                                        >
                                                                            Open
                                                                            System
                                                                            Settings
                                                                        </button>
                                                                    )}
                                                                </span>
                                                            )}
                                                        </div>
                                                        <button
                                                            type="button"
                                                            disabled={
                                                                pending !== null
                                                            }
                                                            className="text-xs text-rose-300 underline"
                                                            onClick={() =>
                                                                void send(
                                                                    `mix-remove:${input.id}`,
                                                                    {
                                                                        command:
                                                                            "removeMixInput",
                                                                        ...selectedTarget,
                                                                        kind: input.kind,
                                                                        sourceID:
                                                                            input.id,
                                                                    },
                                                                )
                                                            }
                                                        >
                                                            Remove
                                                        </button>
                                                    </div>
                                                    <label className="flex items-center gap-3 text-xs">
                                                        Source level{" "}
                                                        <input
                                                            type="range"
                                                            min="0"
                                                            max="1"
                                                            step="0.01"
                                                            value={input.level}
                                                            aria-label={`${name} source level`}
                                                            disabled={
                                                                pending !== null
                                                            }
                                                            onPointerUp={(
                                                                event,
                                                            ) =>
                                                                void send(
                                                                    `mix-level:${input.id}`,
                                                                    {
                                                                        command:
                                                                            "setMixInputLevel",
                                                                        ...selectedTarget,
                                                                        kind: input.kind,
                                                                        sourceID:
                                                                            input.id,
                                                                        level: Number(
                                                                            event
                                                                                .currentTarget
                                                                                .value,
                                                                        ),
                                                                    },
                                                                )
                                                            }
                                                            onChange={(
                                                                event,
                                                            ) => {
                                                                const level =
                                                                    Number(
                                                                        event
                                                                            .currentTarget
                                                                            .value,
                                                                    );
                                                                setMixerState(
                                                                    (state) =>
                                                                        state && {
                                                                            ...state,
                                                                            mixes: state.mixes.map(
                                                                                (
                                                                                    mix,
                                                                                ) =>
                                                                                    mix.target ===
                                                                                        selectedTarget.target &&
                                                                                    mix.id ===
                                                                                        selectedTarget.id
                                                                                        ? {
                                                                                              ...mix,
                                                                                              inputs: mix.inputs.map(
                                                                                                  (
                                                                                                      row,
                                                                                                  ) =>
                                                                                                      row.kind ===
                                                                                                          input.kind &&
                                                                                                      row.id ===
                                                                                                          input.id
                                                                                                          ? {
                                                                                                                ...row,
                                                                                                                level,
                                                                                                            }
                                                                                                          : row,
                                                                                              ),
                                                                                          }
                                                                                        : mix,
                                                                            ),
                                                                        },
                                                                );
                                                            }}
                                                        />
                                                        <span>
                                                            {Math.round(
                                                                input.level *
                                                                    100,
                                                            )}
                                                            %
                                                        </span>
                                                    </label>
                                                    {input.kind !== "bus" && (
                                                        <label className="mt-2 flex items-center gap-2 text-xs">
                                                            Mono placement{" "}
                                                            <select
                                                                value={
                                                                    input.monoPlacement
                                                                }
                                                                disabled={
                                                                    pending !==
                                                                    null
                                                                }
                                                                onChange={(
                                                                    event,
                                                                ) =>
                                                                    void send(
                                                                        `mono:${input.id}`,
                                                                        {
                                                                            command:
                                                                                "setMonoPlacement",
                                                                            ...selectedTarget,
                                                                            kind: input.kind,
                                                                            sourceID:
                                                                                input.id,
                                                                            monoPlacement:
                                                                                event
                                                                                    .currentTarget
                                                                                    .value as
                                                                                    | "left"
                                                                                    | "right"
                                                                                    | "both",
                                                                        },
                                                                    )
                                                                }
                                                                className="rounded border border-slate-700 bg-slate-950 px-2 py-1"
                                                            >
                                                                <option value="both">
                                                                    Stereo
                                                                </option>
                                                                <option value="left">
                                                                    Left
                                                                </option>
                                                                <option value="right">
                                                                    Right
                                                                </option>
                                                            </select>
                                                        </label>
                                                    )}
                                                </li>
                                            );
                                        })}
                                    </ul>
                                )}
                            </section>
                        )}

                        {selectedBus ||
                        selectedRoute ||
                        selectedItem === "bus:new" ? null : !mixerState ? (
                            <div
                                role="status"
                                className="rounded-2xl border border-slate-800 bg-slate-900 p-6 text-sm text-slate-400"
                            >
                                Waiting for the native device snapshot…
                            </div>
                        ) : !selectedOutput ? (
                            <div className="rounded-2xl border border-slate-800 bg-slate-900 p-6 text-sm text-slate-300">
                                Select an output device from the left to open
                                its settings.
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
                                    .filter(
                                        (output) =>
                                            !output.isBlackHole &&
                                            output.uid === selectedOutput?.uid,
                                    )
                                    .map((output) => (
                                        <li
                                            key={output.uid}
                                            className={`flex flex-wrap items-center gap-4 rounded-2xl border bg-slate-900 px-5 py-4 ${selectedItem === `output:${output.uid}` ? "border-sky-300" : "border-slate-800"} ${output.configured && !output.available ? "opacity-60" : ""}`}
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
                                                {!output.available && (
                                                    <p className="w-full text-xs text-amber-300">
                                                        {output.configured
                                                            ? "Saved mix is inactive while this device is disconnected. It will resume when the same device returns."
                                                            : "This device is disconnected."}
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
                                                <>
                                                    <label className="flex min-w-48 flex-1 items-center gap-3 text-xs text-slate-300">
                                                        <span>
                                                            Master level
                                                        </span>
                                                        <input
                                                            type="range"
                                                            min="0"
                                                            max="1"
                                                            step="0.01"
                                                            value={output.level}
                                                            aria-label={`${output.name} master level`}
                                                            aria-valuetext={`${Math.round(output.level * 100)} percent`}
                                                            disabled={
                                                                pending !==
                                                                    null ||
                                                                !output.available
                                                            }
                                                            onChange={(
                                                                event,
                                                            ) => {
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
                                                            onKeyUp={(
                                                                event,
                                                            ) => {
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
                                                                output.level *
                                                                    100,
                                                            )}
                                                            %
                                                        </span>
                                                    </label>
                                                    <button
                                                        type="button"
                                                        disabled={
                                                            pending !== null
                                                        }
                                                        className="text-xs text-rose-300 underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:opacity-50"
                                                        onClick={() => {
                                                            const confirmed =
                                                                window.confirm(
                                                                    `Remove the saved mix for “${output.name}”? This removes only Sound Mixer settings; it does not remove the device.`,
                                                                );
                                                            if (confirmed) {
                                                                void send(
                                                                    `output-delete:${output.uid}`,
                                                                    {
                                                                        command:
                                                                            "deleteOutputMix",
                                                                        uid: output.uid,
                                                                    },
                                                                );
                                                            }
                                                        }}
                                                    >
                                                        Remove saved mix
                                                    </button>
                                                </>
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
                                                    <button
                                                        type="button"
                                                        aria-pressed={
                                                            application.muted
                                                        }
                                                        aria-label={`${application.muted ? "Unmute" : "Mute"} ${application.name} globally`}
                                                        className="mr-4 rounded-lg border border-slate-700 px-3 py-1 text-sm"
                                                        onClick={() =>
                                                            void window.soundMixerBridge?.send(
                                                                {
                                                                    command:
                                                                        "setSourceMuted",
                                                                    kind: "application",
                                                                    sourceID:
                                                                        application.id,
                                                                    muted: !application.muted,
                                                                },
                                                            )
                                                        }
                                                    >
                                                        {application.muted
                                                            ? "Unmute"
                                                            : "Mute"}
                                                    </button>
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
