import { memo } from "react";
import { ItemGroup } from "./ItemGroup";
import { OutputDeviceCard } from "./OutputDeviceCard";
import { VirtualDestinationCard } from "./VirtualDestinationCard";
import { useMixerStore } from "../store";
import { useMixerCommand } from "../useMixerCommand";

export const DestinationSidebar = memo(function DestinationSidebar() {
    const outputs = useMixerStore((state) => state.mixerState?.outputs) ?? [];
    const devices = useMixerStore((state) => state.mixerState?.devices) ?? [];
    const hiddenUIDs = new Set(
        devices.filter((device) => device.hidden).map((device) => device.uid),
    );
    const buses = useMixerStore((state) => state.mixerState?.buses) ?? [];
    const mixes = useMixerStore((state) => state.mixerState?.mixes) ?? [];
    const selectedItem = useMixerStore((state) => state.selectedItem);
    const setSelectedItem = useMixerStore((state) => state.setSelectedItem);
    const setBusNameDraft = useMixerStore((state) => state.setBusNameDraft);
    const pending = useMixerStore((state) => state.pending);
    const send = useMixerCommand();

    const deleteVirtualItem = async (kind: "bus", id: string, name: string) => {
        const approved = window.confirm(
            `Delete “${name}”? Mixes that use this bus will prevent deletion.`,
        );
        if (!approved) return;
        const accepted = await send(`${kind}-delete:${id}`, {
            command: "deleteBus",
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
                {outputs
                    .filter((output) => !hiddenUIDs.has(output.uid))
                    .map((output) => (
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
                {outputs.filter((output) => !hiddenUIDs.has(output.uid))
                    .length === 0 && (
                    <p className="px-3 text-sm text-slate-500">
                        No output devices.
                    </p>
                )}
            </ItemGroup>
            <ItemGroup title="Virtual">
                {buses.map((bus) => {
                    const mix = mixes.find(
                        (item) => item.target === "bus" && item.id === bus.id,
                    );
                    return (
                        <VirtualDestinationCard
                            key={bus.id}
                            name={bus.name}
                            deleteDisabled={pending !== null}
                            onDelete={() =>
                                void deleteVirtualItem("bus", bus.id, bus.name)
                            }
                            channelCount={bus.channelCount}
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
        </nav>
    );
});
