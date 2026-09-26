import { faVolumeHigh, faVolumeXmark } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import type { OutputState } from "../types";
import { AvailabilityDot } from "./AvailabilityDot";
import { PeakMeter } from "./PeakMeter";
import { StableRange } from "./StableRange";

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
    const volumeAvailable = output.available && output.volumeWritable;
    const muteAvailable = output.available && output.muteWritable;

    return (
        <div
            className={`rounded-lg border px-3 py-2 text-sm ${selected ? "border-sky-300 bg-sky-400/15 ring-1 ring-sky-300" : "border-slate-800 bg-slate-900/70"}`}
        >
            <button
                type="button"
                aria-current={selected ? "true" : undefined}
                onClick={onSelect}
                className="flex w-full min-w-0 items-center gap-2 text-left text-slate-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300"
            >
                <AvailabilityDot available={output.available} />
                <span
                    className="min-w-0 truncate font-medium"
                    title={output.name}
                >
                    {output.name}
                </span>
            </button>
            <p className="mt-1 text-[10px] text-slate-500">Device output</p>
            <PeakMeter
                level={output.levelReading}
                label={`${output.name} device output`}
            />
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
                className="mt-2 flex items-center gap-2"
                title={
                    !output.available
                        ? "Output device is disconnected"
                        : !output.volumeWritable
                          ? "This device has no writable main volume control"
                          : undefined
                }
            >
                <button
                    type="button"
                    className="inline-flex min-h-7 min-w-7 shrink-0 items-center justify-center rounded-md text-slate-300 hover:bg-slate-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sky-300 disabled:opacity-40"
                    aria-label={`${output.muted ? "Unmute" : "Mute"} ${output.name} output device`}
                    aria-pressed={output.muted === true}
                    title={
                        !output.available
                            ? "Output device is disconnected"
                            : !output.muteWritable
                              ? "This device has no writable mute control"
                              : output.muted
                                ? `Unmute ${output.name}`
                                : `Mute ${output.name}`
                    }
                    disabled={!muteAvailable || pending}
                    onClick={() => void onMuteChange(!output.muted)}
                >
                    <FontAwesomeIcon
                        icon={output.muted ? faVolumeXmark : faVolumeHigh}
                    />
                </button>
                <StableRange
                    value={output.volume ?? 0}
                    label={`${output.name} device volume${!output.available ? ", disconnected" : !output.volumeWritable ? ", unavailable" : ""}`}
                    title={
                        !output.available
                            ? "Output device is disconnected"
                            : !output.volumeWritable
                              ? "This device has no writable main volume control"
                              : `${output.name} device volume`
                    }
                    disabled={!volumeAvailable}
                    onCommit={onVolumeChange}
                />
                <span className="w-9 shrink-0 text-right text-xs text-slate-300 tabular-nums">
                    {output.volume === null
                        ? "—"
                        : `${Math.round(output.volume * 100)}%`}
                </span>
            </div>
        </div>
    );
}
