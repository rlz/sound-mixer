import { memo } from "react";
import { faCheck, faPlus, faTrashCan } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { useMixerStore } from "../store";
import { useMixerCommand } from "../useMixerCommand";
import type { MixState } from "../types";
import { ItemCard } from "./ItemCard";
import { LevelControl } from "./LevelControl";

export const VirtualInputSource = memo(function VirtualInputSource({
    busID,
}: {
    busID: string;
}) {
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
    const selectedTarget = selectedOutput
        ? { target: "output" as const, id: selectedOutput.uid }
        : selectedBus
          ? { target: "bus" as const, id: selectedBus.id }
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
    return (
        <>
            {(mixerState?.buses ?? [])
                .filter((bus) => bus.id === busID)
                .map((bus) => {
                    const alreadyInSelectedMix =
                        selectedMix?.inputs.some(
                            (input) =>
                                input.kind === "bus" && input.id === bus.id,
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
                            channelCount={bus.channelCount}
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
                                        void send(`bus-delete:${bus.id}`, {
                                            command: "deleteBus",
                                            id: bus.id,
                                        }).then((accepted) => {
                                            if (accepted) {
                                                setSelectedItem(null);
                                                setBusNameDraft(null);
                                            }
                                        })
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
        </>
    );
});
