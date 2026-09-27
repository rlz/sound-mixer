import { useState } from "react";
import { faTrashCan } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import type { OutputState } from "../types";
import { ItemCard } from "./ItemCard";
import { LevelControl } from "./LevelControl";

type OutputDeviceCardProps = {
    output: OutputState;
    selected: boolean;
    pending: boolean;
    onSelect: () => void;
    onVolumeChange: (level: number) => Promise<boolean>;
    onMuteChange: (muted: boolean) => Promise<boolean>;
    onOpenPrivacySettings: () => void;
    onDelete: () => void;
};

export function OutputDeviceCard({
    output,
    selected,
    pending,
    onSelect,
    onVolumeChange,
    onMuteChange,
    onOpenPrivacySettings,
    onDelete,
}: OutputDeviceCardProps) {
    const [failedVolumeKey, setFailedVolumeKey] = useState<string | null>(null);
    const volumeKey = `${output.uid}:${output.available}:${output.volume}`;
    const volumeWriteFailed = failedVolumeKey === volumeKey;

    const volumeAvailable =
        output.available &&
        output.volumeWritable &&
        output.volume !== null &&
        !volumeWriteFailed;
    const muteAvailable = output.available && output.muteWritable;

    return (
        <ItemCard
            name={output.name}
            type="System"
            level={output.available ? output.levelReading : null}
            levelLabel={`${output.name} system output`}
            available={output.available}
            dimmed={!output.available}
            statusLabel={!output.available ? "Disconnected" : undefined}
            status={output.available ? undefined : "inactive"}
            selected={selected}
            channelCount={output.outputChannels}
            trailingAction={
                !output.available && output.configured ? (
                    <button
                        type="button"
                        disabled={pending}
                        aria-label={`Delete ${output.name} mix`}
                        title="Delete mix"
                        className="flex h-7 w-7 shrink-0 items-center justify-center rounded text-rose-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-rose-300 disabled:opacity-50"
                        onClick={onDelete}
                    >
                        <FontAwesomeIcon icon={faTrashCan} aria-hidden="true" />
                    </button>
                ) : undefined
            }
            selectOnSurface
            onSelect={onSelect}
        >
            {output.available &&
                output.meterState?.startsWith("unavailable:") && (
                    <p className="mt-1 text-xs text-amber-300" role="status">
                        Output meter:{" "}
                        {output.meterState.slice("unavailable:".length).trim()}
                    </p>
                )}
            {output.available && output.meterState === "permissionDenied" && (
                <p className="mt-1 text-xs text-amber-300" role="status">
                    Output meter requires System Audio Recording permission.
                </p>
            )}
            {output.available &&
                (output.meterState === "permissionDenied" ||
                    output.meterState?.startsWith("unavailable:")) && (
                    <button
                        type="button"
                        className="mt-1 text-xs text-amber-200 underline"
                        onClick={onOpenPrivacySettings}
                    >
                        Open System Settings
                    </button>
                )}
            <div
                title={
                    output.available && !output.volumeWritable
                        ? "This device has no writable main volume control"
                        : undefined
                }
            >
                <LevelControl
                    name={`${output.name} output device`}
                    displayMode="percent"
                    value={output.volume ?? 0}
                    muted={output.muted === true}
                    muteLabel={
                        output.available && !output.muteWritable
                            ? "This device has no writable mute control"
                            : undefined
                    }
                    muteDisabled={!muteAvailable || pending}
                    onMuteChange={(muted) => void onMuteChange(muted)}
                    levelLabel={`${output.name} device volume${output.available && !output.volumeWritable ? ", unavailable" : ""}`}
                    disabled={!volumeAvailable}
                    displayedValue={
                        output.volume === null
                            ? "—"
                            : `${Math.round(output.volume * 100)}%`
                    }
                    onLevelChange={async (level) => {
                        const accepted = await onVolumeChange(level);
                        if (!accepted) setFailedVolumeKey(volumeKey);
                        return accepted;
                    }}
                />
            </div>
        </ItemCard>
    );
}
