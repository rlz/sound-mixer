import { memo } from "react";
import { faCheck, faPlus, faTrashCan } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { useMixerStore } from "../store";
import { useMixerCommand } from "../useMixerCommand";
import type { MixState } from "../types";
import { ItemGroup } from "./ItemGroup";
import { ItemCard } from "./ItemCard";
import { LevelControl } from "./LevelControl";

export const ApplicationInputsGroup = memo(function ApplicationInputsGroup() {
    const applications =
        useMixerStore((state) => state.mixerState?.applications) ?? [];
    const selectedItem = useMixerStore((state) => state.selectedItem);
    const outputs = useMixerStore((state) => state.mixerState?.outputs) ?? [];
    const buses = useMixerStore((state) => state.mixerState?.buses) ?? [];
    const mixes = useMixerStore((state) => state.mixerState?.mixes) ?? [];
    const pending = useMixerStore((state) => state.pending);
    const send = useMixerCommand();
    const selectedOutput = outputs.find(
        (output) => selectedItem === `output:${output.uid}`,
    );
    const selectedBus = buses.find((bus) => selectedItem === `bus:${bus.id}`);
    const selectedTarget = selectedOutput
        ? { target: "output" as const, id: selectedOutput.uid }
        : selectedBus
          ? { target: "bus" as const, id: selectedBus.id }
          : null;
    const selectedMix: MixState | null = selectedTarget
        ? (mixes.find(
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
    const sourceApplications = applications.filter(
        (application) => application.registered,
    );
    const addSourceToSelectedMix = (kind: string, sourceID: string) => {
        if (!selectedTarget || pending !== null) return;
        void send(`mix-add:${sourceID}`, {
            command: "addMixInput",
            ...selectedTarget,
            kind,
            sourceID,
        });
    };
    const removeApplication = async (id: string, name: string) => {
        if (!window.confirm(`Remove “${name}” and delete it from all mixes?`)) {
            return;
        }
        await send(`app-remove:${id}`, {
            command: "removeApplicationInput",
            applicationID: id,
        });
    };
    return (
        <>
            <ItemGroup title="Applications">
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
                                    : application.captureState === "capturing"
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
                            trailingAction={
                                <button
                                    type="button"
                                    disabled={pending !== null}
                                    aria-label={`Remove ${application.name}`}
                                    title="Remove application"
                                    className="flex h-7 w-7 shrink-0 items-center justify-center rounded text-rose-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-rose-300 disabled:opacity-50"
                                    onClick={() =>
                                        void removeApplication(
                                            application.id,
                                            application.name,
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
                            {(application.captureState.startsWith(
                                "unavailable:",
                            ) ||
                                application.captureState ===
                                    "permissionDenied") && (
                                <p
                                    className="mt-1 text-xs text-amber-200"
                                    role="status"
                                >
                                    {application.captureState ===
                                    "permissionDenied"
                                        ? "System Audio Recording permission denied."
                                        : application.captureState
                                              .slice("unavailable:".length)
                                              .trim()}
                                </p>
                            )}
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
                                    void send(`mute-app:${application.id}`, {
                                        command: "setSourceMuted",
                                        kind: "app",
                                        sourceID: application.id,
                                        muted,
                                    })
                                }
                                onLevelChange={(level) =>
                                    send(
                                        `source-level:application:${application.id}`,
                                        {
                                            command: "setSourceLevel",
                                            kind: "application",
                                            sourceID: application.id,
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
        </>
    );
});
