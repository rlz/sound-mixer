import { memo } from "react";
import {
    faCheck,
    faPlus,
    faTrashCan,
    faVolumeHigh,
    faVolumeXmark,
} from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { useMixerStore } from "../store";
import { useMixerCommand } from "../useMixerCommand";
import type { MixState } from "../types";
import { ItemCard } from "./ItemCard";
import { LevelControl } from "./LevelControl";

export const VirtualInputSources = memo(function VirtualInputSources() {
    const mixerState = useMixerStore((state) => state.mixerState);
    const selectedItem = useMixerStore((state) => state.selectedItem);
    const setSelectedItem = useMixerStore((state) => state.setSelectedItem);
    const setBusNameDraft = useMixerStore((state) => state.setBusNameDraft);
    const pending = useMixerStore((state) => state.pending);
    const send = useMixerCommand();
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
    const selectedMix: MixState | null = selectedTarget
        ? (mixerState?.mixes.find(
              (mix) =>
                  mix.target === selectedTarget.target &&
                  mix.id === selectedTarget.id,
          ) ?? {
              ...selectedTarget,
              level: 1,
              inputs: [],
              levelReading: null,
          })
        : null;
    const addSourceToSelectedMix = (kind: string, sourceID: string) => {
        if (!selectedTarget || pending !== null) return;
        void send(`mix-add:${sourceID}`, {
            command: "addMixInput",
            ...selectedTarget,
            kind,
            sourceID,
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
    return (
        <>
            {(mixerState?.buses ?? []).map((bus) => {
                const alreadyInSelectedMix =
                    selectedMix?.inputs.some(
                        (input) => input.kind === "bus" && input.id === bus.id,
                    ) ?? false;
                const busMix = mixerState?.mixes.find(
                    (mix) => mix.target === "bus" && mix.id === bus.id,
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
                                    (selectedTarget.target === "bus" &&
                                        selectedTarget.id === bus.id)
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
                                    addSourceToSelectedMix("bus", bus.id)
                                }
                            >
                                <FontAwesomeIcon
                                    icon={
                                        alreadyInSelectedMix ? faCheck : faPlus
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
                                void send(`bus-mute:${bus.id}`, {
                                    command: "setSourceMuted",
                                    kind: "bus",
                                    sourceID: bus.id,
                                    muted,
                                })
                            }
                            onLevelChange={(level) =>
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
                            levelLabel={`${bus.name} virtual bus mix gain`}
                        />
                    </ItemCard>
                );
            })}
            {(mixerState?.blackHoleRoutes ?? []).map((route) => {
                const alreadyInSelectedMix =
                    selectedMix?.inputs.some(
                        (input) =>
                            input.kind === "blackHoleRoute" &&
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
                            captureState.startsWith("unavailable:")
                                ? "problem"
                                : captureState === "capturing"
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
                                void send(`mute-route:${route.id}`, {
                                    command: "setSourceMuted",
                                    kind: "blackHoleRoute",
                                    sourceID: route.id,
                                    muted: !route.muted,
                                })
                            }
                        >
                            <FontAwesomeIcon
                                icon={
                                    route.muted ? faVolumeXmark : faVolumeHigh
                                }
                                aria-hidden="true"
                            />
                        </button>
                        {!route.available && (
                            <p
                                className="mt-1 text-xs text-amber-200"
                                role="status"
                            >
                                Input channels {route.channels.join("/")}{" "}
                                unavailable
                            </p>
                        )}
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
                                        command: "setVirtualMixLevel",
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
                                icon={alreadyInSelectedMix ? faCheck : faPlus}
                                aria-hidden="true"
                            />
                        </button>
                    </ItemCard>
                );
            })}
        </>
    );
});
