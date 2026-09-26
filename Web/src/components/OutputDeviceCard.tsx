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
};

export function OutputDeviceCard({
    output,
    selected,
    pending,
    onSelect,
    onVolumeChange,
    onMuteChange,
}: OutputDeviceCardProps) {
    const volumeAvailable = output.available && output.volumeWritable;
    const muteAvailable = output.available && output.muteWritable;

    return (
        <div
            className={`item-panel rounded-lg border px-3 py-2 text-sm ${selected ? "border-sky-300 bg-sky-400/15 ring-1 ring-sky-300" : "border-slate-800"}`}
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
            <PeakMeter
                level={output.levelReading}
                label={`${output.name} output`}
            />
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
                    className="icon-button shrink-0 text-slate-300 hover:bg-slate-700 disabled:opacity-40"
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
                <span className="w-9 shrink-0 text-right text-xs tabular-nums text-slate-300">
                    {output.volume === null
                        ? "—"
                        : `${Math.round(output.volume * 100)}%`}
                </span>
            </div>
        </div>
    );
}
