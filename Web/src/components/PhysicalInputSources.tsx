import { memo } from "react";
import { faCheck, faPlus } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { useMixerStore } from "../store";
import { useMixerCommand } from "../useMixerCommand";
import type { MixState } from "../types";
import { ItemCard } from "./ItemCard";
import { LevelControl } from "./LevelControl";

export const PhysicalInputSources = memo(function PhysicalInputSources() {
    const mixerState = useMixerStore((state) => state.mixerState);
    const selectedItem = useMixerStore((state) => state.selectedItem);
    const pending = useMixerStore((state) => state.pending);
    const send = useMixerCommand();
    const configuredInputIDs = new Set(
        (mixerState?.mixes ?? [])
            .flatMap((mix) => mix.inputs)
            .filter((input) => input.kind === "inputDevice")
            .map((input) => input.id),
    );
    const sourceDevices = (mixerState?.devices ?? []).filter(
        (device) =>
            device.inputChannels > 0 || configuredInputIDs.has(device.uid),
    );
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
            {sourceDevices.map((device) => {
                const inputState = mixerState?.inputCaptureStates.find(
                    (state) => state.uid === device.uid,
                );
                const captureState = inputState?.state ?? "stopped";
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
                            captureState === "permissionDenied" ||
                            captureState.startsWith("unavailable:")
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
                                        alreadyInSelectedMix ? faCheck : faPlus
                                    }
                                    aria-hidden="true"
                                />
                            </button>
                        }
                    >
                        {captureState === "permissionDenied" && (
                            <button
                                type="button"
                                className="text-xs text-amber-200 underline"
                                onClick={() =>
                                    void send(`privacy-input:${device.uid}`, {
                                        command: "openPrivacySettings",
                                    })
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
                                void send(`mute-input:${device.uid}`, {
                                    command: "setSourceMuted",
                                    kind: "inputDevice",
                                    sourceID: device.uid,
                                    muted,
                                })
                            }
                            onLevelChange={(level) =>
                                send(
                                    `source-level:${device.uid}`,
                                    {
                                        command: "setSourceLevel",
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
        </>
    );
});
