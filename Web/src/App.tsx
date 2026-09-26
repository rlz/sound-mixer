import { useEffect, useState } from "react";
import {
    faVolumeHigh,
    faVolumeXmark,
    faPen,
    faTrashCan,
    faArrowRotateLeft,
    faPlus,
    faCheck,
    faXmark,
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
import { OutputDeviceCard } from "./components/OutputDeviceCard";
import { VirtualDestinationCard } from "./components/VirtualDestinationCard";
import { ItemCard } from "./components/ItemCard";
import { LevelControl } from "./components/LevelControl";
import {
    decibelsToGain,
    formatGainDecibels,
    gainToDecibels,
} from "./components/audioGain";
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
    const [routeDeviceUID, setRouteDeviceUID] = useState("");
    const [applicationCatalogOpen, setApplicationCatalogOpen] = useState(false);
    const [applicationSearch, setApplicationSearch] = useState("");
    const [openChannelEditor, setOpenChannelEditor] = useState<string | null>(
        null,
    );
    const [renameDialogOpen, setRenameDialogOpen] = useState(false);
    const [notification, setNotification] = useState<string | null>(null);

    useEffect(() => {
        if (!window.soundMixerBridge) return;
        window.soundMixerBridge.onNotification = ({ message }) => {
            setNotification(message);
        };
    }, []);

    useEffect(() => {
        if (!notification) return;
        const timeout = window.setTimeout(() => setNotification(null), 5000);
        return () => window.clearTimeout(timeout);
    }, [notification]);

    const send = async (
        key: string,
        command: BridgeCommand,
        rollback?: () => void,
        concurrent = false,
    ): Promise<boolean> => {
        if (!window.soundMixerBridge || (!concurrent && pending)) return false;
        if (!concurrent) setPending(key);
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
            if (!concurrent) setPending(null);
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
    const deviceNames = new Map(
        mixerState?.devices.map((device) => [device.uid, device.name]) ?? [],
    );
    const routesByID = new Map(
        mixerState?.blackHoleRoutes.map((route) => [route.id, route]) ?? [],
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
        (mixerState?.mixes.find(
            (mix) =>
                mix.target === selectedTarget.target &&
                mix.id === selectedTarget.id,
        ) ?? {
            ...selectedTarget,
            level: 1,
            inputs: [],
            levelReading: null,
        });
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
    const deleteVirtualItem = async (
        kind: "bus" | "route",
        id: string,
        name: string,
    ) => {
        const approved = window.confirm(
            kind === "route"
                ? `Delete “${name}” and its saved mix? This also removes it as a source from every mix that uses it.`
                : `Delete “${name}”? Mixes that use this bus will prevent deletion.`,
        );
        if (!approved) return;
        const accepted = await send(`${kind}-delete:${id}`, {
            command: kind === "route" ? "deleteRoute" : "deleteBus",
            id,
        });
        if (accepted) {
            setSelectedItem(null);
            setBusNameDraft(null);
        }
    };
    const configuredInputIDs = new Set(
        (mixerState?.mixes ?? [])
            .flatMap((mix) => mix.inputs)
            .filter((input) => input.kind === "inputDevice")
            .map((input) => input.id),
    );
    const configuredApplicationIDs = new Set(
        (mixerState?.applications ?? [])
            .filter((application) => application.registered)
            .map((application) => application.id),
    );
    const sourceDevices = (mixerState?.devices ?? []).filter(
        (device) =>
            device.category === "system" &&
            (device.inputChannels > 0 || configuredInputIDs.has(device.uid)),
    );
    const sourceApplications = (mixerState?.applications ?? []).filter(
        (application) => application.registered,
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
        <main className="flex h-dvh min-h-0 w-full flex-col overflow-hidden bg-slate-950 text-slate-100">
            {notification && (
                <div
                    className="fixed top-4 right-4 z-50 flex max-w-md items-start gap-3 rounded-lg border border-amber-700 bg-slate-900 px-4 py-3 text-sm text-amber-100 shadow-xl"
                    role="status"
                    aria-live="polite"
                >
                    <p className="flex-1">{notification}</p>
                    <button
                        type="button"
                        aria-label="Dismiss notification"
                        title="Dismiss notification"
                        className="flex h-6 w-6 shrink-0 items-center justify-center rounded text-amber-200 hover:bg-slate-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300"
                        onClick={() => setNotification(null)}
                    >
                        <FontAwesomeIcon icon={faXmark} aria-hidden="true" />
                    </button>
                </div>
            )}
            <section className="flex min-h-0 flex-1 flex-col">
                <div className="flex min-h-14 items-center justify-between gap-4 border-b border-slate-700 bg-slate-900 px-4 py-2">
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

                <div className="grid min-h-0 flex-1 grid-cols-3 overflow-hidden">
                    <nav
                        aria-label="Mixer items"
                        className="min-h-0 min-w-0 [scrollbar-gutter:stable] space-y-3.5 overflow-x-hidden overflow-y-auto overscroll-contain border-r border-slate-700 bg-slate-900 p-3.5"
                    >
                        <ItemGroup title="System">
                            {mixerState?.outputs
                                .filter((output) => !output.isBlackHole)
                                .map((output) => (
                                    <OutputDeviceCard
                                        key={output.uid}
                                        output={output}
                                        selected={
                                            selectedItem ===
                                            `output:${output.uid}`
                                        }
                                        pending={pending !== null}
                                        onSelect={() => {
                                            setSelectedItem(
                                                `output:${output.uid}`,
                                            );
                                            setBusNameDraft(null);
                                        }}
                                        onVolumeChange={(level) =>
                                            send(
                                                `device-volume:${output.uid}`,
                                                {
                                                    command: "setDeviceVolume",
                                                    uid: output.uid,
                                                    level,
                                                },
                                                undefined,
                                                true,
                                            )
                                        }
                                        onMuteChange={(muted) =>
                                            send(`device-mute:${output.uid}`, {
                                                command: "setDeviceMuted",
                                                uid: output.uid,
                                                muted,
                                            })
                                        }
                                        onOpenPrivacySettings={() =>
                                            void send(
                                                `privacy-output:${output.uid}`,
                                                {
                                                    command:
                                                        "openPrivacySettings",
                                                },
                                            )
                                        }
                                    />
                                ))}
                            {mixerState?.outputs.every(
                                (output) => output.isBlackHole,
                            ) && (
                                <p className="px-3 text-sm text-slate-500">
                                    No output devices.
                                </p>
                            )}
                        </ItemGroup>
                        <ItemGroup title="Virtual">
                            <button
                                type="button"
                                disabled={pending !== null}
                                onClick={() => {
                                    void send("bus-create", {
                                        command: "createBus",
                                    });
                                }}
                                className="w-full rounded-lg px-3 py-2 text-left text-sm text-sky-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:opacity-50"
                            >
                                + Add virtual bus
                            </button>
                            {mixerState?.buses.map((bus) => {
                                const mix = mixerState.mixes.find(
                                    (item) =>
                                        item.target === "bus" &&
                                        item.id === bus.id,
                                );
                                return (
                                    <VirtualDestinationCard
                                        key={bus.id}
                                        name={bus.name}
                                        kind="bus"
                                        deleteDisabled={pending !== null}
                                        onDelete={() =>
                                            void deleteVirtualItem(
                                                "bus",
                                                bus.id,
                                                bus.name,
                                            )
                                        }
                                        channelCount={2}
                                        muted={bus.muted}
                                        selected={
                                            selectedItem === `bus:${bus.id}`
                                        }
                                        gain={mix?.level ?? 1}
                                        level={mix?.levelReading ?? null}
                                        onSelect={() => {
                                            setSelectedItem(`bus:${bus.id}`);
                                            setBusNameDraft(bus.name);
                                        }}
                                        onGainChange={(level) =>
                                            send(
                                                `virtual-level:${bus.id}`,
                                                {
                                                    command:
                                                        "setVirtualMixLevel",
                                                    target: "bus",
                                                    id: bus.id,
                                                    level,
                                                },
                                                undefined,
                                                true,
                                            )
                                        }
                                        onMuteChange={(muted) =>
                                            send(`bus-mute:${bus.id}`, {
                                                command: "setBusMuted",
                                                id: bus.id,
                                                muted,
                                            })
                                        }
                                    />
                                );
                            })}
                            {mixerState?.buses.length === 0 && (
                                <p className="px-3 text-sm text-slate-500">
                                    No virtual buses.
                                </p>
                            )}
                        </ItemGroup>
                        <ItemGroup title="BlackHole">
                            <button
                                type="button"
                                disabled={pending !== null}
                                onClick={() => {
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
                            {mixerState?.blackHoleRoutes.map((route) => {
                                const mix = mixerState.mixes.find(
                                    (item) =>
                                        item.target === "route" &&
                                        item.id === route.id,
                                );
                                return (
                                    <VirtualDestinationCard
                                        key={route.id}
                                        name={route.name}
                                        kind="BlackHole route"
                                        deleteDisabled={pending !== null}
                                        onDelete={() =>
                                            void deleteVirtualItem(
                                                "route",
                                                route.id,
                                                route.name,
                                            )
                                        }
                                        channelCount={route.channels.length}
                                        muted={route.muted}
                                        available={route.available}
                                        selected={
                                            selectedItem ===
                                            `blackHole:${route.id}`
                                        }
                                        gain={mix?.level ?? 1}
                                        level={route.level}
                                        captureState={route.captureState}
                                        onSelect={() => {
                                            setSelectedItem(
                                                `blackHole:${route.id}`,
                                            );
                                            setBusNameDraft(route.name);
                                        }}
                                        onGainChange={(level) =>
                                            send(
                                                `virtual-level:${route.id}`,
                                                {
                                                    command:
                                                        "setVirtualMixLevel",
                                                    target: "route",
                                                    id: route.id,
                                                    level,
                                                },
                                                undefined,
                                                true,
                                            )
                                        }
                                        onMuteChange={(muted) =>
                                            send(`mute-route:${route.id}`, {
                                                command: "setSourceMuted",
                                                kind: "blackHoleRoute",
                                                sourceID: route.id,
                                                muted,
                                            })
                                        }
                                    />
                                );
                            })}
                            {mixerState?.blackHoleRoutes.length === 0 && (
                                <p className="px-3 text-sm text-slate-500">
                                    No BlackHole routes.
                                </p>
                            )}
                        </ItemGroup>
                    </nav>
                    <div className="min-h-0 min-w-0 [scrollbar-gutter:stable] overflow-x-hidden overflow-y-auto overscroll-contain bg-slate-950 p-3.5">
                        <div className="mb-6 flex items-start justify-between gap-4">
                            <div>
                                <h1 className="text-xl font-semibold tracking-tight">
                                    {selectedOutput?.name ??
                                        selectedBus?.name ??
                                        selectedRoute?.name ??
                                        "Settings"}
                                </h1>
                                <p className="mt-1 text-sm text-slate-400">
                                    {selectedOutput
                                        ? "System"
                                        : selectedBus
                                          ? "Virtual"
                                          : selectedRoute
                                            ? "BlackHole"
                                            : "Select an output or virtual item."}
                                </p>
                            </div>
                            {selectedTarget && selectedMix && (
                                <div className="flex shrink-0 items-center gap-1">
                                    <button
                                        type="button"
                                        disabled={
                                            pending !== null ||
                                            (selectedMix.inputs.length === 0 &&
                                                selectedMix.level === 1)
                                        }
                                        aria-label="Reset mix settings"
                                        title="Reset mix settings"
                                        className="flex h-8 w-8 items-center justify-center rounded-md text-slate-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:opacity-40"
                                        onClick={() =>
                                            void send(
                                                `mix-reset:${selectedTarget.id}`,
                                                {
                                                    command: "resetMix",
                                                    ...selectedTarget,
                                                },
                                            )
                                        }
                                    >
                                        <FontAwesomeIcon
                                            icon={faArrowRotateLeft}
                                            aria-hidden="true"
                                        />
                                    </button>
                                    {(selectedBus || selectedRoute) && (
                                        <>
                                            <button
                                                type="button"
                                                disabled={pending !== null}
                                                aria-label={`Rename ${selectedBus?.name ?? selectedRoute?.name}`}
                                                title="Edit name"
                                                className="flex h-8 w-8 items-center justify-center rounded-md text-slate-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:opacity-50"
                                                onClick={() => {
                                                    setBusNameDraft(
                                                        selectedBus?.name ??
                                                            selectedRoute?.name ??
                                                            "",
                                                    );
                                                    setRenameDialogOpen(true);
                                                }}
                                            >
                                                <FontAwesomeIcon
                                                    icon={faPen}
                                                    aria-hidden="true"
                                                />
                                            </button>
                                            <button
                                                type="button"
                                                disabled={pending !== null}
                                                aria-label={`Delete ${selectedBus?.name ?? selectedRoute?.name}`}
                                                title="Delete"
                                                className="flex h-8 w-8 items-center justify-center rounded-md text-rose-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-rose-300 disabled:opacity-50"
                                                onClick={() => {
                                                    if (selectedRoute)
                                                        void deleteVirtualItem(
                                                            "route",
                                                            selectedRoute.id,
                                                            selectedRoute.name,
                                                        );
                                                    else if (selectedBus)
                                                        void deleteVirtualItem(
                                                            "bus",
                                                            selectedBus.id,
                                                            selectedBus.name,
                                                        );
                                                }}
                                            >
                                                <FontAwesomeIcon
                                                    icon={faTrashCan}
                                                    aria-hidden="true"
                                                />
                                            </button>
                                        </>
                                    )}
                                </div>
                            )}
                        </div>

                        {selectedItem === "route:new" && (
                            <section
                                className="mb-5 rounded-2xl border border-slate-800 bg-slate-900 p-5"
                                aria-label="Virtual item settings"
                            >
                                <form
                                    className="space-y-3"
                                    onSubmit={(event) => {
                                        event.preventDefault();
                                        void send("route-create", {
                                            command: "createRoute",
                                            deviceUID: routeDeviceUID,
                                        });
                                    }}
                                >
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
                                                    Choose an available device
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
                                                            value={output.uid}
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
                                    <p className="text-xs text-slate-400">
                                        Sound Mixer assigns the lowest free
                                        adjacent stereo pair and names the route
                                        from its channels.
                                    </p>
                                    <button
                                        type="submit"
                                        disabled={pending !== null}
                                        className="rounded-lg bg-sky-300 px-3 py-2 text-sm font-semibold text-slate-950 disabled:opacity-50"
                                    >
                                        Create route
                                    </button>
                                </form>
                            </section>
                        )}

                        {selectedMix && selectedTarget && (
                            <section
                                key={`${selectedTarget.target}:${selectedTarget.id}`}
                                className="mb-5"
                                aria-label="Mix sources"
                            >
                                {selectedMix.inputs.length === 0 ? (
                                    <p className="text-sm text-slate-400">
                                        No sources in this mix. Add one from the
                                        Inputs panel.
                                    </p>
                                ) : (
                                    <ul className="space-y-3">
                                        {selectedMix.inputs.map((input) => {
                                            const sourceRoute = routesByID.get(
                                                input.id,
                                            );
                                            const name =
                                                input.kind === "inputDevice"
                                                    ? (deviceNames.get(
                                                          input.id,
                                                      ) ?? input.id)
                                                    : input.kind === "app"
                                                      ? (mixerState?.applications.find(
                                                            (app) =>
                                                                app.id ===
                                                                input.id,
                                                        )?.name ?? input.id)
                                                      : input.kind ===
                                                          "blackHoleRoute"
                                                        ? (sourceRoute?.name ??
                                                          input.id)
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
                                                    : input.kind === "app"
                                                      ? mixerState?.applications.some(
                                                            (app) =>
                                                                app.id ===
                                                                    input.id &&
                                                                app.available,
                                                        )
                                                      : input.kind ===
                                                          "blackHoleRoute"
                                                        ? sourceRoute?.available
                                                        : true;
                                            const captureState =
                                                input.kind === "inputDevice"
                                                    ? (mixerState?.inputCaptureStates.find(
                                                          (state) =>
                                                              state.uid ===
                                                              input.id,
                                                      )?.state ?? "stopped")
                                                    : input.kind === "app"
                                                      ? (mixerState?.applications.find(
                                                            (app) =>
                                                                app.id ===
                                                                input.id,
                                                        )?.captureState ??
                                                        "stopped")
                                                      : input.kind ===
                                                          "blackHoleRoute"
                                                        ? (sourceRoute?.captureState ??
                                                          "unavailable")
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
                                                    : input.kind === "app"
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
                                                >
                                                    <ItemCard
                                                        name={name}
                                                        type={
                                                            input.kind ===
                                                            "inputDevice"
                                                                ? "System"
                                                                : input.kind ===
                                                                    "blackHoleRoute"
                                                                  ? "BlackHole"
                                                                  : input.kind ===
                                                                      "bus"
                                                                    ? "Virtual"
                                                                    : "Application"
                                                        }
                                                        level={
                                                            input.levelReading
                                                        }
                                                        levelLabel={`${name} mix source`}
                                                        available={available}
                                                        status={
                                                            !available ||
                                                            captureState ===
                                                                "permissionDenied" ||
                                                            captureState.startsWith(
                                                                "unavailable:",
                                                            )
                                                                ? "problem"
                                                                : captureState ===
                                                                    "capturing"
                                                                  ? "active"
                                                                  : "inactive"
                                                        }
                                                        channelCount={
                                                            channelCount ||
                                                            (input.kind ===
                                                            "inputDevice"
                                                                ? undefined
                                                                : 2)
                                                        }
                                                        trailingAction={
                                                            <button
                                                                type="button"
                                                                aria-label={`Remove ${name} from mix`}
                                                                title="Remove from mix"
                                                                className="flex h-7 w-7 shrink-0 items-center justify-center rounded text-rose-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-rose-300"
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
                                                                <FontAwesomeIcon
                                                                    icon={
                                                                        faTrashCan
                                                                    }
                                                                    aria-hidden="true"
                                                                />
                                                            </button>
                                                        }
                                                    >
                                                        <span
                                                            className={`text-xs ${input.muted || input.sourceMuted ? "text-amber-300" : available ? "text-emerald-300" : "text-amber-300"}`}
                                                        >
                                                            {input.muted ||
                                                            input.sourceMuted
                                                                ? "Muted"
                                                                : available
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

                                                        <LevelControl
                                                            name={name}
                                                            value={input.level}
                                                            muted={input.muted}
                                                            onMuteChange={(
                                                                muted,
                                                            ) => {
                                                                void send(
                                                                    `mix-input-mute:${selectedMix.target}:${selectedMix.id}:${input.kind}:${input.id}`,
                                                                    {
                                                                        command:
                                                                            "setMixInputMuted",
                                                                        target: selectedMix.target,
                                                                        id: selectedMix.id,
                                                                        kind:
                                                                            input.kind ===
                                                                            "app"
                                                                                ? "application"
                                                                                : input.kind,
                                                                        sourceID:
                                                                            input.id,
                                                                        muted,
                                                                    },
                                                                );
                                                            }}
                                                            levelLabel={`${name} source volume`}
                                                            onLevelChange={(
                                                                value,
                                                            ) =>
                                                                send(
                                                                    `mix-level:${input.id}`,
                                                                    {
                                                                        command:
                                                                            "setMixInputLevel",
                                                                        ...selectedTarget,
                                                                        kind: input.kind,
                                                                        sourceID:
                                                                            input.id,
                                                                        level: value,
                                                                    },
                                                                    undefined,
                                                                    true,
                                                                )
                                                            }
                                                        />
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
                                                                                                value={gainToDecibels(
                                                                                                    input.channelsLinked
                                                                                                        ? linkedLevel
                                                                                                        : (levels[
                                                                                                              index
                                                                                                          ] ??
                                                                                                              1),
                                                                                                )}
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
                                                                                                    decibels,
                                                                                                ) => {
                                                                                                    const value =
                                                                                                        decibelsToGain(
                                                                                                            decibels,
                                                                                                        );
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
                                                                                                min={
                                                                                                    -60
                                                                                                }
                                                                                                max={
                                                                                                    0
                                                                                                }
                                                                                                step={
                                                                                                    0.5
                                                                                                }
                                                                                                formatValue={
                                                                                                    formatGainDecibels
                                                                                                }
                                                                                            />
                                                                                            <span>
                                                                                                {formatGainDecibels(
                                                                                                    gainToDecibels(
                                                                                                        levels[
                                                                                                            index
                                                                                                        ] ??
                                                                                                            1,
                                                                                                    ),
                                                                                                )}
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
                                                            "app" && (
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
                                                    </ItemCard>
                                                </li>
                                            );
                                        })}
                                    </ul>
                                )}
                            </section>
                        )}
                    </div>
                    <aside
                        className="min-h-0 min-w-0 [scrollbar-gutter:stable] space-y-3.5 overflow-x-hidden overflow-y-auto overscroll-contain border-l border-slate-700 bg-slate-900 p-3.5"
                        aria-label="Audio sources"
                    >
                        <ItemGroup title="System">
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
                                    <ItemCard
                                        key={device.uid}
                                        name={device.name}
                                        type="System"
                                        level={inputState?.level}
                                        levelLabel={`${device.name} input`}
                                        available={device.available}
                                        status={
                                            !device.available ||
                                            captureState ===
                                                "permissionDenied" ||
                                            captureState.startsWith(
                                                "unavailable:",
                                            )
                                                ? "problem"
                                                : captureState === "capturing"
                                                  ? "active"
                                                  : "inactive"
                                        }
                                        channelCount={device.inputChannels}
                                        leadingAction={
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
                                                title={
                                                    alreadyInSelectedMix
                                                        ? "Already in mix"
                                                        : `Add ${device.name} to mix`
                                                }
                                                className="flex h-7 w-7 shrink-0 items-center justify-center rounded text-sky-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:opacity-50"
                                                onClick={() =>
                                                    addSourceToSelectedMix(
                                                        "inputDevice",
                                                        device.uid,
                                                    )
                                                }
                                            >
                                                <FontAwesomeIcon
                                                    icon={
                                                        alreadyInSelectedMix
                                                            ? faCheck
                                                            : faPlus
                                                    }
                                                    aria-hidden="true"
                                                />
                                            </button>
                                        }
                                    >
                                        {(!device.available ||
                                            captureState !== "stopped") && (
                                            <p className="mt-1 text-xs text-slate-400">
                                                {!device.available
                                                    ? "Disconnected"
                                                    : captureState ===
                                                        "capturing"
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
                                                          : captureState ===
                                                              "idle"
                                                            ? "No signal"
                                                            : "Starting"}
                                            </p>
                                        )}
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
                                        <LevelControl
                                            name={device.name}
                                            value={device.sourceLevel}
                                            muted={device.muted}
                                            onMuteChange={(muted) =>
                                                void send(
                                                    `mute-input:${device.uid}`,
                                                    {
                                                        command:
                                                            "setSourceMuted",
                                                        kind: "inputDevice",
                                                        sourceID: device.uid,
                                                        muted,
                                                    },
                                                )
                                            }
                                            onLevelChange={(level) =>
                                                send(
                                                    `source-level:${device.uid}`,
                                                    {
                                                        command:
                                                            "setSourceLevel",
                                                        kind: "inputDevice",
                                                        sourceID: device.uid,
                                                        level,
                                                    },
                                                    undefined,
                                                    true,
                                                )
                                            }
                                            levelLabel={`${device.name} input volume`}
                                            muteDisabled={pending !== null}
                                        />
                                    </ItemCard>
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
                                    <ItemCard
                                        key={`bus-input:${bus.id}`}
                                        name={bus.name}
                                        type="Virtual"
                                        level={busMix?.levelReading}
                                        levelLabel={`${bus.name} output`}
                                        channelCount={2}
                                        leadingAction={
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
                                                title={
                                                    alreadyInSelectedMix
                                                        ? "Already in mix"
                                                        : `Add ${bus.name} to mix`
                                                }
                                                className="flex h-7 w-7 shrink-0 items-center justify-center rounded text-sky-300 hover:bg-slate-800 disabled:opacity-50"
                                                onClick={() =>
                                                    addSourceToSelectedMix(
                                                        "bus",
                                                        bus.id,
                                                    )
                                                }
                                            >
                                                <FontAwesomeIcon
                                                    icon={
                                                        alreadyInSelectedMix
                                                            ? faCheck
                                                            : faPlus
                                                    }
                                                    aria-hidden="true"
                                                />
                                            </button>
                                        }
                                        trailingAction={
                                            <button
                                                type="button"
                                                disabled={pending !== null}
                                                aria-label={`Delete ${bus.name}`}
                                                title="Delete"
                                                className="flex h-7 w-7 shrink-0 items-center justify-center rounded text-rose-300 hover:bg-slate-800 disabled:opacity-50"
                                                onClick={() =>
                                                    void deleteVirtualItem(
                                                        "bus",
                                                        bus.id,
                                                        bus.name,
                                                    )
                                                }
                                            >
                                                <FontAwesomeIcon
                                                    icon={faTrashCan}
                                                    aria-hidden="true"
                                                />
                                            </button>
                                        }
                                    >
                                        <LevelControl
                                            name={bus.name}
                                            value={bus.sourceLevel}
                                            muted={bus.muted}
                                            onMuteChange={(muted) =>
                                                void send(
                                                    `bus-mute:${bus.id}`,
                                                    {
                                                        command:
                                                            "setSourceMuted",
                                                        kind: "bus",
                                                        sourceID: bus.id,
                                                        muted,
                                                    },
                                                )
                                            }
                                            onLevelChange={(level) =>
                                                send(
                                                    `virtual-level:${bus.id}`,
                                                    {
                                                        command:
                                                            "setVirtualMixLevel",
                                                        target: "bus",
                                                        id: bus.id,
                                                        level,
                                                    },
                                                    undefined,
                                                    true,
                                                )
                                            }
                                            levelLabel={`${bus.name} virtual bus mix gain`}
                                        />
                                    </ItemCard>
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
                                        <ItemCard
                                            key={route.id}
                                            name={route.name}
                                            type="BlackHole"
                                            level={route.level}
                                            levelLabel={`${route.name} input pair`}
                                            available={route.available}
                                            status={
                                                !route.available ||
                                                captureState.startsWith(
                                                    "unavailable:",
                                                )
                                                    ? "problem"
                                                    : captureState ===
                                                        "capturing"
                                                      ? "active"
                                                      : "inactive"
                                            }
                                            channelCount={route.channels.length}
                                            trailingAction={
                                                <button
                                                    type="button"
                                                    disabled={pending !== null}
                                                    aria-label={`Delete ${route.name}`}
                                                    title="Delete"
                                                    className="flex h-7 w-7 shrink-0 items-center justify-center rounded text-rose-300 hover:bg-slate-800 disabled:opacity-50"
                                                    onClick={() =>
                                                        void deleteVirtualItem(
                                                            "route",
                                                            route.id,
                                                            route.name,
                                                        )
                                                    }
                                                >
                                                    <FontAwesomeIcon
                                                        icon={faTrashCan}
                                                        aria-hidden="true"
                                                    />
                                                </button>
                                            }
                                        >
                                            <button
                                                type="button"
                                                disabled={pending !== null}
                                                aria-pressed={route.muted}
                                                aria-label={`${route.muted ? "Unmute" : "Mute"} ${route.name} globally`}
                                                title={`${route.muted ? "Unmute" : "Mute"} ${route.name} globally`}
                                                className="inline-flex min-h-7 min-w-7 items-center justify-center rounded-md text-sky-300 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sky-300 disabled:opacity-50"
                                                onClick={() =>
                                                    void send(
                                                        `mute-route:${route.id}`,
                                                        {
                                                            command:
                                                                "setSourceMuted",
                                                            kind: "blackHoleRoute",
                                                            sourceID: route.id,
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
                                            <LevelControl
                                                name={route.name}
                                                value={route.sourceLevel}
                                                muted={route.muted}
                                                showMute={false}
                                                onMuteChange={() => undefined}
                                                onLevelChange={(level) =>
                                                    send(
                                                        `virtual-level:${route.id}`,
                                                        {
                                                            command:
                                                                "setVirtualMixLevel",
                                                            target: "route",
                                                            id: route.id,
                                                            level,
                                                        },
                                                        undefined,
                                                        true,
                                                    )
                                                }
                                                levelLabel={`${route.name} BlackHole route mix gain`}
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
                                                title={
                                                    alreadyInSelectedMix
                                                        ? "Already in mix"
                                                        : `Add ${route.name} to mix`
                                                }
                                                className="mt-1 flex h-8 w-8 items-center justify-center rounded text-sky-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:cursor-not-allowed disabled:opacity-50"
                                                onClick={() =>
                                                    addSourceToSelectedMix(
                                                        "blackHoleRoute",
                                                        route.id,
                                                    )
                                                }
                                            >
                                                <FontAwesomeIcon
                                                    icon={
                                                        alreadyInSelectedMix
                                                            ? faCheck
                                                            : faPlus
                                                    }
                                                    aria-hidden="true"
                                                />
                                            </button>
                                        </ItemCard>
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
                                            input.kind === "app" &&
                                            input.id === application.id,
                                    ) ?? false;
                                return (
                                    <ItemCard
                                        key={application.id}
                                        name={application.name}
                                        type="Application"
                                        level={application.level}
                                        levelLabel={`${application.name} input`}
                                        available={application.available}
                                        status={
                                            !application.available ||
                                            application.captureState ===
                                                "permissionDenied" ||
                                            application.captureState.startsWith(
                                                "unavailable:",
                                            )
                                                ? "problem"
                                                : application.captureState ===
                                                    "capturing"
                                                  ? "active"
                                                  : "inactive"
                                        }
                                        channelCount={2}
                                        leadingAction={
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
                                                title={
                                                    alreadyInSelectedMix
                                                        ? "Already in mix"
                                                        : `Add ${application.name} to mix`
                                                }
                                                className="flex h-7 w-7 shrink-0 items-center justify-center rounded text-sky-300 hover:bg-slate-800 disabled:opacity-50"
                                                onClick={() =>
                                                    addSourceToSelectedMix(
                                                        "app",
                                                        application.id,
                                                    )
                                                }
                                            >
                                                <FontAwesomeIcon
                                                    icon={
                                                        alreadyInSelectedMix
                                                            ? faCheck
                                                            : faPlus
                                                    }
                                                    aria-hidden="true"
                                                />
                                            </button>
                                        }
                                    >
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
                                        <LevelControl
                                            name={application.name}
                                            value={application.sourceLevel}
                                            maxGainDecibels={30}
                                            muted={application.muted}
                                            showMute
                                            onMuteChange={(muted) =>
                                                void send(
                                                    `mute-app:${application.id}`,
                                                    {
                                                        command:
                                                            "setSourceMuted",
                                                        kind: "app",
                                                        sourceID:
                                                            application.id,
                                                        muted,
                                                    },
                                                )
                                            }
                                            onLevelChange={(level) =>
                                                send(
                                                    `source-level:application:${application.id}`,
                                                    {
                                                        command:
                                                            "setSourceLevel",
                                                        kind: "application",
                                                        sourceID:
                                                            application.id,
                                                        level,
                                                    },
                                                    undefined,
                                                    true,
                                                )
                                            }
                                            levelLabel={`${application.name} input volume`}
                                        />
                                    </ItemCard>
                                );
                            })}
                        </ItemGroup>
                    </aside>
                </div>
            </section>
            {renameDialogOpen && (selectedBus || selectedRoute) && (
                <div
                    className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4"
                    onMouseDown={(event) => {
                        if (event.target === event.currentTarget) {
                            setRenameDialogOpen(false);
                        }
                    }}
                >
                    <section
                        role="dialog"
                        aria-modal="true"
                        aria-labelledby="rename-destination-title"
                        onKeyDown={(event) => {
                            if (event.key === "Escape")
                                setRenameDialogOpen(false);
                        }}
                        className="w-full max-w-md rounded-xl border border-slate-700 bg-slate-900 p-4 shadow-2xl"
                    >
                        <form
                            onSubmit={async (event) => {
                                event.preventDefault();
                                const succeeded = selectedRoute
                                    ? await send("route-rename", {
                                          command: "renameRoute",
                                          id: selectedRoute.id,
                                          name: busNameDraft ?? "",
                                      })
                                    : selectedBus
                                      ? await send("bus-rename", {
                                            command: "renameBus",
                                            id: selectedBus.id,
                                            name: busNameDraft ?? "",
                                        })
                                      : false;
                                if (succeeded) setRenameDialogOpen(false);
                            }}
                        >
                            <h2
                                id="rename-destination-title"
                                className="text-base font-semibold"
                            >
                                Rename{" "}
                                {selectedBus
                                    ? "virtual bus"
                                    : "BlackHole route"}
                            </h2>
                            <label
                                className="mt-3 block text-sm"
                                htmlFor="rename-destination-input"
                            >
                                Name
                                <input
                                    autoFocus
                                    id="rename-destination-input"
                                    maxLength={64}
                                    required
                                    value={busNameDraft ?? ""}
                                    onChange={(event) =>
                                        setBusNameDraft(
                                            event.currentTarget.value,
                                        )
                                    }
                                    className="mt-1 w-full rounded-lg border border-slate-600 bg-slate-950 px-3 py-2 text-slate-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300"
                                />
                            </label>
                            <div className="mt-4 flex justify-end gap-2">
                                <button
                                    type="button"
                                    onClick={() => setRenameDialogOpen(false)}
                                    className="rounded-lg border border-slate-700 px-3 py-2 text-sm text-slate-200"
                                >
                                    Cancel
                                </button>
                                <button
                                    type="submit"
                                    disabled={pending !== null}
                                    className="rounded-lg bg-sky-300 px-3 py-2 text-sm font-semibold text-slate-950 disabled:opacity-50"
                                >
                                    Save name
                                </button>
                            </div>
                        </form>
                    </section>
                </div>
            )}
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
                                        disabled={pending !== null}
                                        className="shrink-0 rounded bg-sky-300 px-3 py-1.5 text-sm font-semibold text-slate-950 disabled:opacity-50"
                                        onClick={() => {
                                            void send(
                                                `app-register:${application.id}`,
                                                {
                                                    command:
                                                        "addApplicationInput",
                                                    applicationID:
                                                        application.id,
                                                },
                                            );
                                            setApplicationCatalogOpen(false);
                                        }}
                                    >
                                        Add input
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
