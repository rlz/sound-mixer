import { memo } from "react";
import { ItemGroup } from "./ItemGroup";
import { OutputDeviceCard } from "./OutputDeviceCard";
import { VirtualDestinationCard } from "./VirtualDestinationCard";
import { useMixerStore } from "../store";
import { useMixerCommand } from "../useMixerCommand";

export const DestinationSidebar = memo(function DestinationSidebar() {
    const outputs = useMixerStore((state) => state.mixerState?.outputs) ?? [];
    const buses = useMixerStore((state) => state.mixerState?.buses) ?? [];
    const routes =
        useMixerStore((state) => state.mixerState?.blackHoleRoutes) ?? [];
    const mixes = useMixerStore((state) => state.mixerState?.mixes) ?? [];
    const selectedItem = useMixerStore((state) => state.selectedItem);
    const setSelectedItem = useMixerStore((state) => state.setSelectedItem);
    const setBusNameDraft = useMixerStore((state) => state.setBusNameDraft);
    const setRouteDeviceUID = useMixerStore((state) => state.setRouteDeviceUID);
    const pending = useMixerStore((state) => state.pending);
    const send = useMixerCommand();

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

    return (
        <nav
            aria-label="Mixer items"
            className="min-h-0 min-w-0 [scrollbar-gutter:stable] space-y-3.5 overflow-x-hidden overflow-y-auto overscroll-contain border-r border-slate-700 bg-slate-900 p-3.5"
        >
            <ItemGroup title="System">
                {outputs.map((output) => (
                    <OutputDeviceCard
                        key={output.uid}
                        output={output}
                        selected={selectedItem === `output:${output.uid}`}
                        pending={pending !== null}
                        onSelect={() => {
                            setSelectedItem(`output:${output.uid}`);
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
                            void send(`privacy-output:${output.uid}`, {
                                command: "openPrivacySettings",
                            })
                        }
                    />
                ))}
                {outputs.length === 0 && (
                    <p className="px-3 text-sm text-slate-500">
                        No output devices.
                    </p>
                )}
            </ItemGroup>
            <ItemGroup title="Virtual">
                <button
                    type="button"
                    disabled={pending !== null}
                    onClick={() =>
                        void send("bus-create", { command: "createBus" })
                    }
                    className="w-full rounded-lg px-3 py-2 text-left text-sm text-sky-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:opacity-50"
                >
                    + Add virtual bus
                </button>
                {buses.map((bus) => {
                    const mix = mixes.find(
                        (item) => item.target === "bus" && item.id === bus.id,
                    );
                    return (
                        <VirtualDestinationCard
                            key={bus.id}
                            name={bus.name}
                            kind="bus"
                            deleteDisabled={pending !== null}
                            onDelete={() =>
                                void deleteVirtualItem("bus", bus.id, bus.name)
                            }
                            channelCount={2}
                            muted={bus.muted}
                            selected={selectedItem === `bus:${bus.id}`}
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
                                        command: "setVirtualMixLevel",
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
                {buses.length === 0 && (
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
                            outputs.find(
                                (output) =>
                                    output.isBlackHole && output.available,
                            )?.uid ?? "",
                        );
                    }}
                    className="w-full rounded-lg px-3 py-2 text-left text-sm text-sky-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:opacity-50"
                >
                    + Add BlackHole route
                </button>
                {routes.map((route) => {
                    const mix = mixes.find(
                        (item) =>
                            item.target === "route" && item.id === route.id,
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
                            selected={selectedItem === `blackHole:${route.id}`}
                            gain={mix?.level ?? 1}
                            level={route.level}
                            captureState={route.captureState}
                            onSelect={() => {
                                setSelectedItem(`blackHole:${route.id}`);
                                setBusNameDraft(route.name);
                            }}
                            onGainChange={(level) =>
                                send(
                                    `virtual-level:${route.id}`,
                                    {
                                        command: "setVirtualMixLevel",
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
                {routes.length === 0 && (
                    <p className="px-3 text-sm text-slate-500">
                        No BlackHole routes.
                    </p>
                )}
            </ItemGroup>
        </nav>
    );
});
