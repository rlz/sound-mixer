import { useState } from "react";
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
};

export function OutputDeviceCard({
    output,
    selected,
    pending,
    onSelect,
    onVolumeChange,
    onMuteChange,
    onOpenPrivacySettings,
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
            level={output.levelReading}
            levelLabel={`${output.name} system output`}
            available={output.available}
            selected={selected}
            channelCount={output.outputChannels}
            onSelect={onSelect}
        >
            {output.meterState?.startsWith("unavailable:") && (
                <p className="mt-1 text-xs text-amber-300" role="status">
                    Output meter:{" "}
                    {output.meterState.slice("unavailable:".length).trim()}
                </p>
            )}
            {output.meterState === "permissionDenied" && (
                <p className="mt-1 text-xs text-amber-300" role="status">
                    Output meter requires System Audio Recording permission.
                </p>
            )}
            {(output.meterState === "permissionDenied" ||
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
                    !output.available
                        ? "Output device is disconnected"
                        : !output.volumeWritable
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
                        !output.available
                            ? "Output device is disconnected"
                            : !output.muteWritable
                              ? "This device has no writable mute control"
                              : undefined
                    }
                    muteDisabled={!muteAvailable || pending}
                    onMuteChange={(muted) => void onMuteChange(muted)}
                    levelLabel={`${output.name} device volume${!output.available ? ", disconnected" : !output.volumeWritable ? ", unavailable" : ""}`}
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
