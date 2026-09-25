import { useEffect, useState } from "react";
import {
    faVolumeHigh,
    faVolumeXmark,
    faMicrophone,
    faDesktop,
} from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { useMixerStore } from "./store";
import type { BridgeCommand } from "./types";
import "./bridge";
import { ItemGroup } from "./components/ItemGroup";
import { AppHeader } from "./components/AppHeader";
import { MasterSwitch } from "./components/MasterSwitch";
import { PeakMeter } from "./components/PeakMeter";
import { StableRange } from "./components/StableRange";
import "./styles.css";

const applicationGainToDecibels = (gain: number) =>
    gain <= 0 ? -60 : Math.max(-60, 20 * Math.log10(gain));

const formatApplicationGain = (decibels: number) =>
    decibels <= -60
        ? "Mute"
        : `${decibels > 0 ? "+" : ""}${decibels.toFixed(1)} dB`;

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
    const [routeDeviceUID, setRouteDeviceUID] = useState("");
    const [applicationCatalogOpen, setApplicationCatalogOpen] = useState(false);
    const [applicationSearch, setApplicationSearch] = useState("");
    const [openChannelEditor, setOpenChannelEditor] = useState<string | null>(
        null,
    );

    const send = async (
        key: string,
        command: BridgeCommand,
        rollback?: () => void,
    ): Promise<boolean> => {
        if (!window.soundMixerBridge || pending) return false;
        setPending(key);
        setCommandError(null);
        try {
            await window.soundMixerBridge.send(command);
            return true;
        } catch (error) {
            rollback?.();
            setCommandError(
                error instanceof Error
                    ? error.message
                    : "The change could not be saved.",
            );
            return false;
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
    const addSourceToSelectedMix = (kind: string, sourceID: string) => {
        if (!selectedTarget || pending !== null) return;
        void send(`mix-add:${sourceID}`, {
            command: "addMixInput",
            ...selectedTarget,
            kind,
            sourceID,
            monoPlacement: "both",
        });
    };
    const sourceChoice = useMixerStore((state) => state.sourceChoice);
    const setSourceChoice = useMixerStore((state) => state.setSourceChoice);
    const configuredInputIDs = new Set(
        (mixerState?.mixes ?? [])
            .flatMap((mix) => mix.inputs)
            .filter((input) => input.kind === "inputDevice")
            .map((input) => input.id),
    );
    const configuredApplicationIDs = new Set(
        (mixerState?.mixes ?? [])
            .flatMap((mix) => mix.inputs)
            .filter((input) => input.kind === "application")
            .map((input) => input.id),
    );
    const sourceDevices = (mixerState?.devices ?? []).filter(
        (device) =>
            device.inputChannels > 0 || configuredInputIDs.has(device.uid),
    );
    const sourceApplications = [...configuredApplicationIDs].map(
        (id) =>
            mixerState?.applications.find(
                (application) => application.id === id,
            ) ?? {
                id,
                name: id,
                available: false,
                muted: false,
                captureState: "stopped",
                level: null,
            },
    );
    const availableApplications = (mixerState?.applications ?? [])
        .filter((application) => application.available)
        .filter((application) => !configuredApplicationIDs.has(application.id))
        .filter((application) =>
            `${application.name} ${application.id}`
                .toLocaleLowerCase()
                .includes(applicationSearch.trim().toLocaleLowerCase()),
        );

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

    useEffect(() => {
        if (selectedItem !== null || !mixerState) return;
        const firstDestination =
            mixerState.outputs.find(
                (output) => output.available && !output.isBlackHole,
            ) ??
            mixerState.buses[0] ??
            mixerState.blackHoleRoutes[0];
        if (!firstDestination) return;
        if ("uid" in firstDestination) {
            setSelectedItem(`output:${firstDestination.uid}`);
        } else if ("deviceUID" in firstDestination) {
            setSelectedItem(`blackHole:${firstDestination.id}`);
        } else {
            setSelectedItem(`bus:${firstDestination.id}`);
        }
    }, [mixerState, selectedItem, setSelectedItem]);

    return (
        <main className="app-shell text-slate-100">
            <section className="app-content">
                <div className="app-toolbar">
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
                </div>

                {commandError && (
                    <p
                        className="border-b border-rose-800 bg-rose-950 px-5 py-2 text-sm text-rose-200"
                        role="alert"
                    >
                        {commandError}
                    </p>
                )}

                <div className="mixer-workspace">
                    <nav
                        aria-label="Mixer items"
                        className="mixer-pane mixer-pane-left space-y-5"
                    >
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
                                        className={`item-panel flex w-full items-center justify-between gap-3 rounded-lg border px-3 py-2 text-left text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 ${selectedItem === `output:${output.uid}` ? "border-sky-300 bg-sky-400/15 text-sky-100 ring-1 ring-sky-300" : "border-slate-800 text-slate-300 hover:bg-slate-800"}`}
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
                                    className={`item-panel w-full rounded-lg border px-3 py-2 text-left text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 ${selectedItem === `bus:${bus.id}` ? "border-sky-300 bg-sky-400/15 text-sky-100 ring-1 ring-sky-300" : "border-slate-800 text-slate-300 hover:bg-slate-800"}`}
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
                            <button
                                type="button"
                                disabled={pending !== null}
                                onClick={() => {
                                    setEditingBusId(null);
                                    setEditingRouteId(null);
                                    setSelectedItem("route:new");
                                    setRouteDeviceUID(
                                        mixerState?.outputs.find(
                                            (output) =>
                                                output.isBlackHole &&
                                                output.available,
                                        )?.uid ?? "",
                                    );
                                }}
                                className="w-full rounded-lg px-3 py-2 text-left text-sm text-sky-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:opacity-50"
                            >
                                + Add BlackHole route
                            </button>
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
                                    className={`item-panel w-full rounded-lg border px-3 py-2 text-left text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 ${selectedItem === `blackHole:${route.id}` ? "border-sky-300 bg-sky-400/15 text-sky-100 ring-1 ring-sky-300" : "border-slate-800 text-slate-300 hover:bg-slate-800"}`}
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
                    <div className="mixer-pane mixer-pane-center">
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
                            selectedItem === "bus:new" ||
                            selectedItem === "route:new") && (
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
                                        } else if (
                                            selectedItem === "route:new"
                                        ) {
                                            void send("route-create", {
                                                command: "createRoute",
                                                deviceUID: routeDeviceUID,
                                            });
                                        } else {
                                            void send("bus-create", {
                                                command: "createBus",
                                                name: busNameDraft ?? "",
                                            });
                                        }
                                    }}
                                >
                                    {selectedItem !== "route:new" && (
                                        <label
                                            htmlFor="selected-virtual-name"
                                            className="block text-sm font-medium text-slate-200"
                                        >
                                            {selectedRoute
                                                ? "Route name"
                                                : "Virtual bus name"}
                                        </label>
                                    )}
                                    <input
                                        id="selected-virtual-name"
                                        maxLength={64}
                                        required={selectedItem !== "route:new"}
                                        hidden={selectedItem === "route:new"}
                                        value={
                                            selectedItem === "route:new"
                                                ? ""
                                                : (busNameDraft ??
                                                  selectedBus?.name ??
                                                  selectedRoute?.name ??
                                                  "")
                                        }
                                        onChange={(event) =>
                                            setBusNameDraft(
                                                event.currentTarget.value,
                                            )
                                        }
                                        className="w-full rounded-lg border border-slate-600 bg-slate-950 px-3 py-2 text-sm text-slate-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300"
                                    />
                                    {selectedItem === "route:new" && (
                                        <div className="grid gap-3 sm:grid-cols-2">
                                            <label className="text-sm">
                                                BlackHole device
                                                <select
                                                    required
                                                    value={routeDeviceUID}
                                                    onChange={(event) =>
                                                        setRouteDeviceUID(
                                                            event.currentTarget
                                                                .value,
                                                        )
                                                    }
                                                    className="mt-1 w-full rounded-lg border border-slate-600 bg-slate-950 px-3 py-2 text-slate-100"
                                                >
                                                    <option value="">
                                                        Choose an available
                                                        device
                                                    </option>
                                                    {mixerState?.outputs
                                                        .filter(
                                                            (output) =>
                                                                output.isBlackHole &&
                                                                output.available,
                                                        )
                                                        .map((output) => (
                                                            <option
                                                                key={output.uid}
                                                                value={
                                                                    output.uid
                                                                }
                                                            >
                                                                {output.name} ·{" "}
                                                                {
                                                                    output.outputChannels
                                                                }{" "}
                                                                channels
                                                            </option>
                                                        ))}
                                                </select>
                                            </label>
                                        </div>
                                    )}
                                    {selectedItem === "route:new" && (
                                        <p className="text-xs text-slate-400">
                                            Sound Mixer assigns the lowest free
                                            adjacent stereo pair and names the
                                            route from its channels.
                                        </p>
                                    )}
                                    {selectedRoute && (
                                        <p className="font-mono text-xs text-slate-500">
                                            Core Audio UID:{" "}
                                            {selectedRoute.deviceUID} · channels{" "}
                                            {selectedRoute.channels.join(" / ")}
                                        </p>
                                    )}
                                    <button
                                        type="submit"
                                        disabled={pending !== null}
                                        className="rounded-lg bg-sky-300 px-3 py-2 text-sm font-semibold text-slate-950 disabled:opacity-50"
                                    >
                                        {selectedItem === "route:new"
                                            ? "Create route"
                                            : "Save name"}
                                    </button>
                                    {selectedRoute && (
                                        <button
                                            type="button"
                                            disabled={pending !== null}
                                            onClick={() => {
                                                if (
                                                    window.confirm(
                                                        `Delete “${selectedRoute.name}” and its saved mix? This also removes it as a source from every mix that uses it.`,
                                                    )
                                                ) {
                                                    void send(
                                                        `route-delete:${selectedRoute.id}`,
                                                        {
                                                            command:
                                                                "deleteRoute",
                                                            id: selectedRoute.id,
                                                        },
                                                    );
                                                }
                                            }}
                                            className="ml-3 rounded-lg border border-rose-800 px-3 py-2 text-sm text-rose-200"
                                        >
                                            Delete route
                                        </button>
                                    )}
                                </form>
                            </section>
                        )}

                        {selectedMix && selectedTarget && (
                            <section
                                className="mb-5 rounded-2xl border border-slate-800 bg-slate-900 p-5"
                                aria-label="Mix sources"
                            >
                                <PeakMeter
                                    level={selectedMix.levelReading}
                                    label="Destination output"
                                />
                                {selectedTarget.target !== "output" && (
                                    <label className="mb-3 flex items-center gap-3 text-xs text-slate-300">
                                        Mix gain
                                        <StableRange
                                            value={selectedMix.level}
                                            label="Virtual destination mix gain"
                                            onCommit={(level) =>
                                                send(
                                                    `virtual-level:${selectedTarget.id}`,
                                                    {
                                                        command:
                                                            "setVirtualMixLevel",
                                                        target: selectedTarget.target as
                                                            | "bus"
                                                            | "route",
                                                        id: selectedTarget.id,
                                                        level,
                                                    },
                                                )
                                            }
                                        />
                                        <span className="w-9 text-right tabular-nums">
                                            {Math.round(
                                                selectedMix.level * 100,
                                            )}
                                            %
                                        </span>
                                    </label>
                                )}
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
                                            {mixerState?.blackHoleRoutes.map(
                                                (route) => (
                                                    <option
                                                        key={`route:${route.id}`}
                                                        value={`blackHoleRoute|${route.id}`}
                                                    >
                                                        {route.name} · BlackHole
                                                        input pair
                                                    </option>
                                                ),
                                            )}
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
                                        input or virtual bus above.
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
                                            const channelCount =
                                                input.kind === "inputDevice"
                                                    ? (mixerState?.devices.find(
                                                          (device) =>
                                                              device.uid ===
                                                              input.id,
                                                      )?.inputChannels ?? 0)
                                                    : 0;
                                            const routing = Array.from(
                                                {
                                                    length: Math.max(
                                                        channelCount,
                                                        input.channelRouting
                                                            .length,
                                                    ),
                                                },
                                                (_, index) =>
                                                    input.channelRouting[
                                                        index
                                                    ] ?? "ignore",
                                            );
                                            const levels = Array.from(
                                                { length: routing.length },
                                                (_, index) =>
                                                    input.channelLevels[
                                                        index
                                                    ] ?? 1,
                                            );
                                            const editorKey = `${selectedTarget.target}:${selectedTarget.id}:${input.id}`;
                                            const linkedLevel = Math.max(
                                                0,
                                                ...levels,
                                            );
                                            const scaleLinkedLevels = (
                                                value: number,
                                            ) => {
                                                return linkedLevel > 0
                                                    ? levels.map((level) =>
                                                          Math.min(
                                                              1,
                                                              (level * value) /
                                                                  linkedLevel,
                                                          ),
                                                      )
                                                    : levels.map(() => value);
                                            };
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
                                                    className="item-panel rounded-xl border border-slate-800 p-3"
                                                >
                                                    <PeakMeter
                                                        level={
                                                            input.levelReading
                                                        }
                                                        label={`${name} mix source`}
                                                    />
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
                                                        {input.kind ===
                                                        "application"
                                                            ? "App gain"
                                                            : "Source level"}{" "}
                                                        <StableRange
                                                            value={
                                                                input.kind ===
                                                                "application"
                                                                    ? applicationGainToDecibels(
                                                                          input.level,
                                                                      )
                                                                    : input.level
                                                            }
                                                            label={`${name} ${input.kind === "application" ? "app gain" : "source level"}`}
                                                            min={
                                                                input.kind ===
                                                                "application"
                                                                    ? -60
                                                                    : 0
                                                            }
                                                            max={
                                                                input.kind ===
                                                                "application"
                                                                    ? 30
                                                                    : 1
                                                            }
                                                            step={
                                                                input.kind ===
                                                                "application"
                                                                    ? 0.5
                                                                    : 0.01
                                                            }
                                                            formatValue={
                                                                input.kind ===
                                                                "application"
                                                                    ? formatApplicationGain
                                                                    : undefined
                                                            }
                                                            onCommit={(value) =>
                                                                send(
                                                                    `mix-level:${input.id}`,
                                                                    {
                                                                        command:
                                                                            "setMixInputLevel",
                                                                        ...selectedTarget,
                                                                        kind: input.kind,
                                                                        sourceID:
                                                                            input.id,
                                                                        level:
                                                                            input.kind ===
                                                                            "application"
                                                                                ? value <=
                                                                                  -60
                                                                                    ? 0
                                                                                    : Math.pow(
                                                                                          10,
                                                                                          value /
                                                                                              20,
                                                                                      )
                                                                                : value,
                                                                    },
                                                                )
                                                            }
                                                        />
                                                        <span>
                                                            {input.kind ===
                                                            "application"
                                                                ? formatApplicationGain(
                                                                      applicationGainToDecibels(
                                                                          input.level,
                                                                      ),
                                                                  )
                                                                : `${Math.round(input.level * 100)}%`}
                                                        </span>
                                                    </label>
                                                    {input.kind ===
                                                        "inputDevice" && (
                                                        <div className="mt-3">
                                                            <button
                                                                type="button"
                                                                aria-expanded={
                                                                    openChannelEditor ===
                                                                    editorKey
                                                                }
                                                                aria-controls={`channels-${input.id}`}
                                                                className="rounded border border-slate-700 px-2 py-1 text-xs text-sky-200 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300"
                                                                onClick={() =>
                                                                    setOpenChannelEditor(
                                                                        openChannelEditor ===
                                                                            editorKey
                                                                            ? null
                                                                            : editorKey,
                                                                    )
                                                                }
                                                            >
                                                                Channels (
                                                                {channelCount ||
                                                                    input
                                                                        .channelRouting
                                                                        .length}
                                                                )
                                                            </button>
                                                            {openChannelEditor ===
                                                                editorKey && (
                                                                <div
                                                                    id={`channels-${input.id}`}
                                                                    className="mt-2 rounded-lg border border-slate-800 bg-slate-950 p-3"
                                                                >
                                                                    <label className="mb-3 flex items-center gap-2 text-xs">
                                                                        <input
                                                                            type="checkbox"
                                                                            checked={
                                                                                input.channelsLinked
                                                                            }
                                                                            onChange={(
                                                                                event,
                                                                            ) => {
                                                                                const linked =
                                                                                    event
                                                                                        .currentTarget
                                                                                        .checked;
                                                                                void send(
                                                                                    `channels:${input.id}`,
                                                                                    {
                                                                                        command:
                                                                                            "setPhysicalInputChannels",
                                                                                        ...selectedTarget,
                                                                                        sourceID:
                                                                                            input.id,
                                                                                        channelRouting:
                                                                                            routing,
                                                                                        channelLevels:
                                                                                            levels,
                                                                                        channelsLinked:
                                                                                            linked,
                                                                                    },
                                                                                );
                                                                            }}
                                                                        />
                                                                        Link
                                                                        gains
                                                                        while
                                                                        preserving
                                                                        relative
                                                                        channel
                                                                        levels
                                                                    </label>
                                                                    <div className="space-y-2">
                                                                        {routing.map(
                                                                            (
                                                                                choice,
                                                                                index,
                                                                            ) => (
                                                                                <div
                                                                                    key={
                                                                                        index
                                                                                    }
                                                                                    className="grid grid-cols-[minmax(9rem,1.2fr)_minmax(7rem,1fr)_minmax(7rem,1fr)] items-center gap-2 text-xs"
                                                                                >
                                                                                    <div className="min-w-0">
                                                                                        <span>
                                                                                            Channel{" "}
                                                                                            {index +
                                                                                                1}
                                                                                        </span>
                                                                                        <PeakMeter
                                                                                            level={
                                                                                                mixerState?.inputCaptureStates.find(
                                                                                                    (
                                                                                                        state,
                                                                                                    ) =>
                                                                                                        state.uid ===
                                                                                                        input.id,
                                                                                                )
                                                                                                    ?.channelLevels[
                                                                                                    index
                                                                                                ]
                                                                                            }
                                                                                            label={`${name} channel ${index + 1}`}
                                                                                        />
                                                                                    </div>
                                                                                    <select
                                                                                        value={
                                                                                            choice
                                                                                        }
                                                                                        aria-label={`Channel ${index + 1} routing`}
                                                                                        disabled={
                                                                                            pending !==
                                                                                            null
                                                                                        }
                                                                                        className="rounded border border-slate-700 bg-slate-900 px-2 py-1"
                                                                                        onChange={(
                                                                                            event,
                                                                                        ) => {
                                                                                            const nextRouting =
                                                                                                [
                                                                                                    ...routing,
                                                                                                ];
                                                                                            nextRouting[
                                                                                                index
                                                                                            ] =
                                                                                                event
                                                                                                    .currentTarget
                                                                                                    .value as typeof choice;
                                                                                            void send(
                                                                                                `channels:${input.id}`,
                                                                                                {
                                                                                                    command:
                                                                                                        "setPhysicalInputChannels",
                                                                                                    ...selectedTarget,
                                                                                                    sourceID:
                                                                                                        input.id,
                                                                                                    channelRouting:
                                                                                                        nextRouting,
                                                                                                    channelLevels:
                                                                                                        levels,
                                                                                                    channelsLinked:
                                                                                                        input.channelsLinked,
                                                                                                },
                                                                                            );
                                                                                        }}
                                                                                    >
                                                                                        <option value="ignore">
                                                                                            Ignore
                                                                                        </option>
                                                                                        <option value="first">
                                                                                            First
                                                                                        </option>
                                                                                        <option value="second">
                                                                                            Second
                                                                                        </option>
                                                                                        <option value="both">
                                                                                            Both
                                                                                        </option>
                                                                                    </select>
                                                                                    <label className="flex items-center gap-2">
                                                                                        <StableRange
                                                                                            value={
                                                                                                input.channelsLinked
                                                                                                    ? linkedLevel
                                                                                                    : (levels[
                                                                                                          index
                                                                                                      ] ??
                                                                                                      1)
                                                                                            }
                                                                                            label={
                                                                                                input.channelsLinked
                                                                                                    ? `${name} linked channel gain, channel 1 reference`
                                                                                                    : `${name} channel ${index + 1} level`
                                                                                            }
                                                                                            disabled={
                                                                                                input.channelsLinked &&
                                                                                                index >
                                                                                                    0
                                                                                            }
                                                                                            onCommit={(
                                                                                                value,
                                                                                            ) => {
                                                                                                const nextLevels =
                                                                                                    input.channelsLinked
                                                                                                        ? scaleLinkedLevels(
                                                                                                              value,
                                                                                                          )
                                                                                                        : [
                                                                                                              ...levels,
                                                                                                          ];
                                                                                                if (
                                                                                                    !input.channelsLinked
                                                                                                ) {
                                                                                                    nextLevels[
                                                                                                        index
                                                                                                    ] =
                                                                                                        value;
                                                                                                }
                                                                                                return send(
                                                                                                    `channels:${input.id}`,
                                                                                                    {
                                                                                                        command:
                                                                                                            "setPhysicalInputChannels",
                                                                                                        ...selectedTarget,
                                                                                                        sourceID:
                                                                                                            input.id,
                                                                                                        channelRouting:
                                                                                                            routing,
                                                                                                        channelLevels:
                                                                                                            nextLevels,
                                                                                                        channelsLinked:
                                                                                                            input.channelsLinked,
                                                                                                    },
                                                                                                );
                                                                                            }}
                                                                                        />
                                                                                        <span>
                                                                                            {Math.round(
                                                                                                (levels[
                                                                                                    index
                                                                                                ] ??
                                                                                                    1) *
                                                                                                    100,
                                                                                            )}

                                                                                            %
                                                                                        </span>
                                                                                    </label>
                                                                                </div>
                                                                            ),
                                                                        )}
                                                                        {channelCount ===
                                                                            0 && (
                                                                            <p className="text-amber-200">
                                                                                Input
                                                                                channels
                                                                                are
                                                                                unavailable.
                                                                                Saved
                                                                                settings
                                                                                are
                                                                                retained.
                                                                            </p>
                                                                        )}
                                                                    </div>
                                                                </div>
                                                            )}
                                                        </div>
                                                    )}
                                                    {input.kind ===
                                                        "application" && (
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
                        selectedItem === "bus:new" ||
                        selectedItem === "route:new" ? null : !mixerState ? (
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
                                                {output.configured && (
                                                    <PeakMeter
                                                        level={
                                                            output.levelReading
                                                        }
                                                        label={`${output.name} output`}
                                                    />
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
                                            <div className="min-w-48 flex-1 text-xs text-slate-300">
                                                <label className="flex items-center gap-3">
                                                    Device volume
                                                    <StableRange
                                                        value={
                                                            output.volume ?? 0
                                                        }
                                                        label={`${output.name} device volume`}
                                                        disabled={
                                                            pending !== null ||
                                                            !output.available ||
                                                            !output.volumeWritable
                                                        }
                                                        onCommit={(level) =>
                                                            send(
                                                                `device-volume:${output.uid}`,
                                                                {
                                                                    command:
                                                                        "setDeviceVolume",
                                                                    uid: output.uid,
                                                                    level,
                                                                },
                                                            )
                                                        }
                                                    />
                                                    <span className="w-9 text-right tabular-nums">
                                                        {output.volume === null
                                                            ? "—"
                                                            : `${Math.round(output.volume * 100)}%`}
                                                    </span>
                                                </label>
                                                {output.available &&
                                                    output.volumeWritable && (
                                                        <p className="mt-1 text-slate-500">
                                                            Previous device
                                                            volume is restored
                                                            on exit.
                                                        </p>
                                                    )}
                                                {output.available &&
                                                    !output.volumeWritable && (
                                                        <p
                                                            className="mt-1 text-amber-300"
                                                            role="status"
                                                        >
                                                            This device has no
                                                            writable main volume
                                                            control.
                                                        </p>
                                                    )}
                                            </div>
                                            {output.configured && (
                                                <button
                                                    type="button"
                                                    disabled={pending !== null}
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
                                            )}
                                        </li>
                                    ))}
                            </ul>
                        )}
                    </div>
                    <aside
                        className="mixer-pane mixer-pane-right space-y-5"
                        aria-label="Audio sources"
                    >
                        <ItemGroup title="Inputs">
                            {sourceDevices.length === 0 &&
                                (mixerState?.buses.length ?? 0) === 0 &&
                                (mixerState?.blackHoleRoutes.length ?? 0) ===
                                    0 && (
                                    <p className="px-3 text-sm text-slate-500">
                                        No inputs found.
                                    </p>
                                )}
                            {sourceDevices.map((device) => {
                                const inputState =
                                    mixerState?.inputCaptureStates.find(
                                        (state) => state.uid === device.uid,
                                    );
                                const captureState =
                                    inputState?.state ?? "stopped";
                                const alreadyInSelectedMix =
                                    selectedMix?.inputs.some(
                                        (input) =>
                                            input.kind === "inputDevice" &&
                                            input.id === device.uid,
                                    ) ?? false;
                                return (
                                    <div
                                        key={device.uid}
                                        className="item-panel rounded-lg border border-slate-800 px-3 py-2"
                                    >
                                        <div className="flex items-start justify-between gap-2">
                                            <span className="flex min-w-0 items-center gap-2 truncate text-sm">
                                                <FontAwesomeIcon
                                                    icon={faMicrophone}
                                                    aria-hidden="true"
                                                    className="text-slate-400"
                                                />
                                                {device.name}
                                            </span>
                                            <button
                                                type="button"
                                                disabled={pending !== null}
                                                aria-pressed={device.muted}
                                                aria-label={`${device.muted ? "Unmute" : "Mute"} ${device.name} globally`}
                                                title={`${device.muted ? "Unmute" : "Mute"} ${device.name} globally`}
                                                className="icon-button text-sky-300 disabled:opacity-50"
                                                onClick={() =>
                                                    void send(
                                                        `mute-input:${device.uid}`,
                                                        {
                                                            command:
                                                                "setSourceMuted",
                                                            kind: "inputDevice",
                                                            sourceID:
                                                                device.uid,
                                                            muted: !device.muted,
                                                        },
                                                    )
                                                }
                                            >
                                                <FontAwesomeIcon
                                                    icon={
                                                        device.muted
                                                            ? faVolumeXmark
                                                            : faVolumeHigh
                                                    }
                                                    aria-hidden="true"
                                                />
                                            </button>
                                        </div>
                                        <p className="mt-1 text-xs text-slate-400">
                                            {!device.available
                                                ? "Disconnected"
                                                : captureState === "capturing"
                                                  ? "Capturing"
                                                  : captureState.startsWith(
                                                          "unavailable:",
                                                      )
                                                    ? captureState
                                                          .slice(
                                                              "unavailable:"
                                                                  .length,
                                                          )
                                                          .trim()
                                                    : captureState ===
                                                        "permissionDenied"
                                                      ? "Permission denied"
                                                      : "Available"}
                                        </p>
                                        {captureState ===
                                            "permissionDenied" && (
                                            <button
                                                type="button"
                                                className="text-xs text-amber-200 underline"
                                                onClick={() =>
                                                    void send(
                                                        `privacy-input:${device.uid}`,
                                                        {
                                                            command:
                                                                "openPrivacySettings",
                                                        },
                                                    )
                                                }
                                            >
                                                Open System Settings
                                            </button>
                                        )}
                                        <PeakMeter
                                            level={inputState?.level}
                                            label={device.name}
                                        />
                                        <button
                                            type="button"
                                            disabled={
                                                !selectedTarget ||
                                                alreadyInSelectedMix ||
                                                pending !== null
                                            }
                                            aria-label={
                                                alreadyInSelectedMix
                                                    ? `${device.name} is already in the selected mix`
                                                    : `Add ${device.name} to the selected mix`
                                            }
                                            className="mt-1 rounded px-2 py-1 text-xs text-sky-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:cursor-not-allowed disabled:opacity-50"
                                            onClick={() =>
                                                addSourceToSelectedMix(
                                                    "inputDevice",
                                                    device.uid,
                                                )
                                            }
                                        >
                                            {alreadyInSelectedMix
                                                ? "Added"
                                                : "Add to mix"}
                                        </button>
                                    </div>
                                );
                            })}
                            {(mixerState?.buses ?? []).map((bus) => {
                                const alreadyInSelectedMix =
                                    selectedMix?.inputs.some(
                                        (input) =>
                                            input.kind === "bus" &&
                                            input.id === bus.id,
                                    ) ?? false;
                                const busMix = mixerState?.mixes.find(
                                    (mix) =>
                                        mix.target === "bus" &&
                                        mix.id === bus.id,
                                );
                                return (
                                    <div
                                        key={`bus-input:${bus.id}`}
                                        className="item-panel rounded-lg border border-slate-800 px-3 py-2"
                                    >
                                        <div className="flex min-w-0 items-center gap-2 truncate text-sm">
                                            <FontAwesomeIcon
                                                icon={faVolumeHigh}
                                                aria-hidden="true"
                                                className="text-slate-400"
                                            />
                                            {bus.name}
                                        </div>
                                        <p className="mt-1 text-xs text-slate-400">
                                            Internal virtual input
                                        </p>
                                        <PeakMeter
                                            level={busMix?.levelReading}
                                            label={`${bus.name} output`}
                                        />
                                        <button
                                            type="button"
                                            disabled={
                                                !selectedTarget ||
                                                alreadyInSelectedMix ||
                                                pending !== null ||
                                                (selectedTarget.target ===
                                                    "bus" &&
                                                    selectedTarget.id ===
                                                        bus.id)
                                            }
                                            aria-label={
                                                alreadyInSelectedMix
                                                    ? `${bus.name} is already in the selected mix`
                                                    : `Add ${bus.name} to the selected mix`
                                            }
                                            className="mt-1 rounded px-2 py-1 text-xs text-sky-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:cursor-not-allowed disabled:opacity-50"
                                            onClick={() =>
                                                addSourceToSelectedMix(
                                                    "bus",
                                                    bus.id,
                                                )
                                            }
                                        >
                                            {alreadyInSelectedMix
                                                ? "Added"
                                                : "Add to mix"}
                                        </button>
                                    </div>
                                );
                            })}
                            {(mixerState?.blackHoleRoutes ?? []).map(
                                (route) => {
                                    const alreadyInSelectedMix =
                                        selectedMix?.inputs.some(
                                            (input) =>
                                                input.kind ===
                                                    "blackHoleRoute" &&
                                                input.id === route.id,
                                        ) ?? false;
                                    const captureState = route.captureState;
                                    return (
                                        <div
                                            key={route.id}
                                            className="item-panel rounded-lg border border-slate-800 px-3 py-2"
                                        >
                                            <div className="flex items-start justify-between gap-2">
                                                <span className="flex min-w-0 items-center gap-2 truncate text-sm">
                                                    <FontAwesomeIcon
                                                        icon={faVolumeHigh}
                                                        aria-hidden="true"
                                                        className="text-slate-400"
                                                    />
                                                    {route.name}
                                                </span>
                                                <button
                                                    type="button"
                                                    disabled={pending !== null}
                                                    aria-pressed={route.muted}
                                                    aria-label={`${route.muted ? "Unmute" : "Mute"} ${route.name} globally`}
                                                    title={`${route.muted ? "Unmute" : "Mute"} ${route.name} globally`}
                                                    className="icon-button text-sky-300 disabled:opacity-50"
                                                    onClick={() =>
                                                        void send(
                                                            `mute-route:${route.id}`,
                                                            {
                                                                command:
                                                                    "setSourceMuted",
                                                                kind: "blackHoleRoute",
                                                                sourceID:
                                                                    route.id,
                                                                muted: !route.muted,
                                                            },
                                                        )
                                                    }
                                                >
                                                    <FontAwesomeIcon
                                                        icon={
                                                            route.muted
                                                                ? faVolumeXmark
                                                                : faVolumeHigh
                                                        }
                                                        aria-hidden="true"
                                                    />
                                                </button>
                                            </div>
                                            <p className="mt-1 text-xs text-slate-400">
                                                {route.available
                                                    ? captureState ===
                                                      "capturing"
                                                        ? `Capturing input channels ${route.channels.join("/")}`
                                                        : captureState.startsWith(
                                                                "unavailable:",
                                                            )
                                                          ? captureState
                                                                .slice(
                                                                    "unavailable:"
                                                                        .length,
                                                                )
                                                                .trim()
                                                          : `Input channels ${route.channels.join("/")} available`
                                                    : `Input channels ${route.channels.join("/")} unavailable`}
                                            </p>
                                            <PeakMeter
                                                level={route.level}
                                                label={`${route.name} input pair`}
                                            />
                                            <button
                                                type="button"
                                                disabled={
                                                    !selectedTarget ||
                                                    alreadyInSelectedMix ||
                                                    pending !== null
                                                }
                                                aria-label={
                                                    alreadyInSelectedMix
                                                        ? `${route.name} is already in the selected mix`
                                                        : `Add ${route.name} to the selected mix`
                                                }
                                                className="mt-1 rounded px-2 py-1 text-xs text-sky-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:cursor-not-allowed disabled:opacity-50"
                                                onClick={() =>
                                                    addSourceToSelectedMix(
                                                        "blackHoleRoute",
                                                        route.id,
                                                    )
                                                }
                                            >
                                                {alreadyInSelectedMix
                                                    ? "Added"
                                                    : "Add to mix"}
                                            </button>
                                        </div>
                                    );
                                },
                            )}
                        </ItemGroup>
                        <ItemGroup title="Applications">
                            <button
                                type="button"
                                disabled={pending !== null}
                                className="mx-3 mb-2 rounded-lg bg-slate-800 px-3 py-2 text-sm text-sky-300 hover:bg-slate-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:opacity-50"
                                onClick={() => {
                                    setApplicationSearch("");
                                    setApplicationCatalogOpen(true);
                                }}
                            >
                                Add application
                            </button>
                            {sourceApplications.length === 0 && (
                                <p className="px-3 text-sm text-slate-500">
                                    No applications have been added.
                                </p>
                            )}
                            {sourceApplications.map((application) => {
                                const alreadyInSelectedMix =
                                    selectedMix?.inputs.some(
                                        (input) =>
                                            input.kind === "application" &&
                                            input.id === application.id,
                                    ) ?? false;
                                return (
                                    <div
                                        key={application.id}
                                        className="item-panel rounded-lg border border-slate-800 px-3 py-2"
                                    >
                                        <div className="flex items-start justify-between gap-2">
                                            <span className="flex min-w-0 items-center gap-2 truncate text-sm">
                                                <FontAwesomeIcon
                                                    icon={faDesktop}
                                                    aria-hidden="true"
                                                    className="text-slate-400"
                                                />
                                                {application.name}
                                            </span>
                                            <button
                                                type="button"
                                                disabled={pending !== null}
                                                aria-pressed={application.muted}
                                                aria-label={`${application.muted ? "Unmute" : "Mute"} ${application.name} globally`}
                                                title={`${application.muted ? "Unmute" : "Mute"} ${application.name} globally`}
                                                className="icon-button text-sky-300 disabled:opacity-50"
                                                onClick={() =>
                                                    void send(
                                                        `mute-app:${application.id}`,
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
                                                <FontAwesomeIcon
                                                    icon={
                                                        application.muted
                                                            ? faVolumeXmark
                                                            : faVolumeHigh
                                                    }
                                                    aria-hidden="true"
                                                />
                                            </button>
                                        </div>
                                        <p
                                            className={`mt-1 text-xs ${application.captureState.startsWith("unavailable:") || application.captureState === "permissionDenied" ? "text-amber-200" : "text-slate-400"}`}
                                            role={
                                                application.captureState.startsWith(
                                                    "unavailable:",
                                                ) ||
                                                application.captureState ===
                                                    "permissionDenied"
                                                    ? "status"
                                                    : undefined
                                            }
                                        >
                                            {!application.available
                                                ? "Application is not running or producing audio."
                                                : application.captureState ===
                                                    "capturing"
                                                  ? "Capturing audio buffers."
                                                  : application.captureState ===
                                                      "starting"
                                                    ? "Starting audio capture…"
                                                    : application.captureState ===
                                                        "permissionDenied"
                                                      ? "System Audio Recording permission denied."
                                                      : application.captureState.startsWith(
                                                              "unavailable:",
                                                          )
                                                        ? application.captureState
                                                              .slice(
                                                                  "unavailable:"
                                                                      .length,
                                                              )
                                                              .trim()
                                                        : "Available"}
                                        </p>
                                        {application.available &&
                                            application.captureState ===
                                                "permissionDenied" && (
                                                <button
                                                    type="button"
                                                    className="mt-1 text-xs text-sky-300 underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300"
                                                    onClick={() =>
                                                        void send(
                                                            `privacy:${application.id}`,
                                                            {
                                                                command:
                                                                    "openPrivacySettings",
                                                            },
                                                        )
                                                    }
                                                >
                                                    Open System Settings
                                                </button>
                                            )}
                                        <PeakMeter
                                            level={application.level}
                                            label={application.name}
                                        />
                                        <button
                                            type="button"
                                            disabled={
                                                !selectedTarget ||
                                                alreadyInSelectedMix ||
                                                pending !== null
                                            }
                                            aria-label={
                                                alreadyInSelectedMix
                                                    ? `${application.name} is already in the selected mix`
                                                    : `Add ${application.name} to the selected mix`
                                            }
                                            className="mt-1 rounded px-2 py-1 text-xs text-sky-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:cursor-not-allowed disabled:opacity-50"
                                            onClick={() =>
                                                addSourceToSelectedMix(
                                                    "application",
                                                    application.id,
                                                )
                                            }
                                        >
                                            {alreadyInSelectedMix
                                                ? "Added"
                                                : "Add to mix"}
                                        </button>
                                    </div>
                                );
                            })}
                        </ItemGroup>
                        <p className="text-xs text-slate-500">
                            Source levels are shown in each destination mix.
                            Capture requires the relevant macOS permission.
                        </p>
                    </aside>
                </div>
            </section>
            {applicationCatalogOpen && (
                <div
                    className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4"
                    onMouseDown={(event) => {
                        if (event.target === event.currentTarget) {
                            setApplicationCatalogOpen(false);
                        }
                    }}
                >
                    <section
                        role="dialog"
                        aria-modal="true"
                        aria-labelledby="application-catalog-title"
                        onKeyDown={(event) => {
                            if (event.key === "Escape") {
                                setApplicationCatalogOpen(false);
                            }
                        }}
                        className="w-full max-w-lg rounded-xl border border-slate-700 bg-slate-900 p-4 shadow-2xl"
                    >
                        <div className="flex items-center justify-between gap-3">
                            <h2
                                id="application-catalog-title"
                                className="text-base font-semibold"
                            >
                                Add an application
                            </h2>
                            <button
                                type="button"
                                className="rounded px-2 py-1 text-sm text-slate-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300"
                                onClick={() => setApplicationCatalogOpen(false)}
                            >
                                Close
                            </button>
                        </div>
                        <label className="mt-3 block text-sm">
                            Search running applications
                            <input
                                autoFocus
                                type="search"
                                value={applicationSearch}
                                onChange={(event) =>
                                    setApplicationSearch(
                                        event.currentTarget.value,
                                    )
                                }
                                placeholder="Name or bundle identifier"
                                className="mt-1 w-full rounded-lg border border-slate-600 bg-slate-950 px-3 py-2 text-slate-100 placeholder:text-slate-500"
                            />
                        </label>
                        <ul className="mt-3 max-h-72 space-y-2 overflow-y-auto">
                            {availableApplications.map((application) => (
                                <li
                                    key={application.id}
                                    className="flex items-center justify-between gap-3 rounded-lg border border-slate-800 px-3 py-2"
                                >
                                    <span className="min-w-0">
                                        <span className="block truncate text-sm">
                                            {application.name}
                                        </span>
                                        <span className="block truncate text-xs text-slate-400">
                                            {application.id}
                                        </span>
                                    </span>
                                    <button
                                        type="button"
                                        disabled={
                                            !selectedTarget || pending !== null
                                        }
                                        className="shrink-0 rounded bg-sky-300 px-3 py-1.5 text-sm font-semibold text-slate-950 disabled:opacity-50"
                                        onClick={() => {
                                            addSourceToSelectedMix(
                                                "application",
                                                application.id,
                                            );
                                            setApplicationCatalogOpen(false);
                                        }}
                                    >
                                        Add to mix
                                    </button>
                                </li>
                            ))}
                            {availableApplications.length === 0 && (
                                <li className="px-2 py-4 text-sm text-slate-400">
                                    {mixerState?.applications.some(
                                        (application) =>
                                            application.available &&
                                            !configuredApplicationIDs.has(
                                                application.id,
                                            ),
                                    )
                                        ? "No applications match this search."
                                        : "No eligible running applications are available."}
                                </li>
                            )}
                        </ul>
                    </section>
                </div>
            )}
        </main>
    );
}
