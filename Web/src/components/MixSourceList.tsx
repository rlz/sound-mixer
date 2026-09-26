import { memo, useState } from "react";
import { faTrashCan } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { useMixerStore } from "../store";
import { useMixerCommand } from "../useMixerCommand";
import { ChannelMatrixDialog } from "./ChannelMatrixDialog";
import { LevelControl } from "./LevelControl";
import { ItemCard } from "./ItemCard";
import type { MixState } from "../types";

export const MixSourceList = memo(function MixSourceList() {
    const mixerState = useMixerStore((state) => state.mixerState);
    const selectedItem = useMixerStore((state) => state.selectedItem);
    const pending = useMixerStore((state) => state.pending);
    const [openChannelEditor, setOpenChannelEditor] = useState<string | null>(
        null,
    );
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
    const deviceNames = new Map(
        mixerState?.devices.map((device) => [device.uid, device.name]) ?? [],
    );
    return (
        <>
            {selectedMix && selectedTarget && (
                <section
                    key={`${selectedTarget.target}:${selectedTarget.id}`}
                    className="mb-5"
                    aria-label="Mix sources"
                >
                    {selectedMix.inputs.length === 0 ? (
                        <p className="text-sm text-slate-400">
                            No sources in this mix. Add one from the Inputs
                            panel.
                        </p>
                    ) : (
                        <ul className="space-y-3">
                            {selectedMix.inputs.map((input) => {
                                const name =
                                    input.kind === "inputDevice"
                                        ? (deviceNames.get(input.id) ??
                                          input.id)
                                        : input.kind === "app"
                                          ? (mixerState?.applications.find(
                                                (app) => app.id === input.id,
                                            )?.name ?? input.id)
                                          : (mixerState?.buses.find(
                                                (bus) => bus.id === input.id,
                                            )?.name ?? input.id);
                                const available =
                                    input.kind === "inputDevice"
                                        ? mixerState?.devices.some(
                                              (device) =>
                                                  device.uid === input.id &&
                                                  device.available,
                                          )
                                        : input.kind === "app"
                                          ? mixerState?.applications.some(
                                                (app) =>
                                                    app.id === input.id &&
                                                    app.available,
                                            )
                                          : true;
                                const captureState =
                                    input.kind === "inputDevice"
                                        ? (mixerState?.inputCaptureStates.find(
                                              (state) => state.uid === input.id,
                                          )?.state ?? "stopped")
                                        : input.kind === "app"
                                          ? (mixerState?.applications.find(
                                                (app) => app.id === input.id,
                                            )?.captureState ?? "stopped")
                                          : "capturing";
                                const channelCount =
                                    input.kind === "inputDevice"
                                        ? (mixerState?.devices.find(
                                              (device) =>
                                                  device.uid === input.id,
                                          )?.inputChannels ?? 0)
                                        : 0;
                                const inputChannels =
                                    input.kind === "inputDevice"
                                        ? Math.max(
                                              channelCount,
                                              input.channelRouting.length,
                                          )
                                        : input.kind === "bus"
                                          ? (mixerState?.buses.find(
                                                (bus) => bus.id === input.id,
                                            )?.channelCount ?? 2)
                                          : 2;
                                const outputChannels =
                                    selectedTarget.target === "output"
                                        ? (mixerState?.outputs.find(
                                              (output) =>
                                                  output.uid ===
                                                  selectedTarget.id,
                                          )?.outputChannels ?? 2)
                                        : 2;
                                const targetChannelCount =
                                    selectedTarget.target === "bus"
                                        ? (mixerState?.buses.find(
                                              (bus) =>
                                                  bus.id === selectedTarget.id,
                                          )?.channelCount ?? 2)
                                        : outputChannels;
                                const routing = Array.from(
                                    { length: inputChannels },
                                    (_, index) =>
                                        input.channelRouting[index] ?? [],
                                );
                                const levels = Array.from(
                                    { length: inputChannels },
                                    (_, index) =>
                                        input.channelLevels[index] ?? 1,
                                );
                                const editorKey = `${selectedTarget.target}:${selectedTarget.id}:${input.id}`;
                                const unavailableReason = !available
                                    ? input.kind === "inputDevice"
                                        ? "Device disconnected."
                                        : input.kind === "app"
                                          ? "Application is not producing audio."
                                          : "Source unavailable."
                                    : captureState === "permissionDenied"
                                      ? "Permission denied. Allow access in System Settings."
                                      : captureState.startsWith("unavailable:")
                                        ? captureState
                                              .slice("unavailable:".length)
                                              .trim()
                                        : null;
                                return (
                                    <li key={`${input.kind}:${input.id}`}>
                                        <ItemCard
                                            name={name}
                                            type={
                                                input.kind === "inputDevice"
                                                    ? "System"
                                                    : input.kind === "bus"
                                                      ? "Virtual"
                                                      : "Application"
                                            }
                                            level={input.levelReading}
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
                                            channelCount={inputChannels}
                                            onChannelClick={() =>
                                                setOpenChannelEditor(editorKey)
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
                                                                kind:
                                                                    input.kind ===
                                                                    "app"
                                                                        ? "app"
                                                                        : "inputDevice",
                                                                sourceID:
                                                                    input.id,
                                                            },
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
                                            {unavailableReason && (
                                                <span
                                                    className="mt-1 block text-xs text-amber-200"
                                                    role="status"
                                                >
                                                    {unavailableReason}
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
                                                            Open System Settings
                                                        </button>
                                                    )}
                                                </span>
                                            )}

                                            <LevelControl
                                                name={name}
                                                value={input.level}
                                                muted={input.muted}
                                                onMuteChange={(muted) => {
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
                                                            sourceID: input.id,
                                                            muted,
                                                        },
                                                    );
                                                }}
                                                levelLabel={`${name} source volume`}
                                                onLevelChange={(value) =>
                                                    send(
                                                        `mix-level:${input.id}`,
                                                        {
                                                            command:
                                                                "setMixInputLevel",
                                                            ...selectedTarget,
                                                            kind: input.kind,
                                                            sourceID: input.id,
                                                            level: value,
                                                        },
                                                        undefined,
                                                        true,
                                                    )
                                                }
                                            />
                                        </ItemCard>
                                        {openChannelEditor === editorKey && (
                                            <ChannelMatrixDialog
                                                name={name}
                                                inputChannels={inputChannels}
                                                outputChannels={
                                                    targetChannelCount
                                                }
                                                routing={routing}
                                                channelLevels={levels}
                                                meters={
                                                    input.kind === "inputDevice"
                                                        ? mixerState?.inputCaptureStates.find(
                                                              (state) =>
                                                                  state.uid ===
                                                                  input.id,
                                                          )?.channelLevels
                                                        : input.kind === "app"
                                                          ? mixerState?.applications.find(
                                                                (app) =>
                                                                    app.id ===
                                                                    input.id,
                                                            )?.channelLevels
                                                          : input.channelMeters
                                                }
                                                disabled={pending !== null}
                                                gainDisabled={false}
                                                onClose={() =>
                                                    setOpenChannelEditor(null)
                                                }
                                                onRoutingChange={(next) =>
                                                    void send(
                                                        `routing:${input.id}`,
                                                        {
                                                            command:
                                                                "setMixInputRouting",
                                                            ...selectedTarget,
                                                            kind: input.kind,
                                                            sourceID: input.id,
                                                            channelRouting:
                                                                next,
                                                        },
                                                    )
                                                }
                                                onGainChange={(next) =>
                                                    send(
                                                        `channels:${input.id}`,
                                                        {
                                                            command:
                                                                "setMixInputChannels",
                                                            ...selectedTarget,
                                                            kind:
                                                                input.kind ===
                                                                "app"
                                                                    ? "app"
                                                                    : input.kind ===
                                                                        "bus"
                                                                      ? "bus"
                                                                      : "inputDevice",
                                                            sourceID: input.id,
                                                            channelLevels: next,
                                                        },
                                                        undefined,
                                                        true,
                                                    )
                                                }
                                            />
                                        )}
                                    </li>
                                );
                            })}
                        </ul>
                    )}
                </section>
            )}
        </>
    );
});
