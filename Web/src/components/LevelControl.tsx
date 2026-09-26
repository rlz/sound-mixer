import { faVolumeHigh, faVolumeXmark } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { StableRange } from "./StableRange";
import {
    decibelsToGain,
    formatGainDecibels,
    gainToDecibels,
    MIN_GAIN_DECIBELS,
} from "./audioGain";

type LevelControlProps = {
    name: string;
    value: number;
    muted: boolean;
    onMuteChange: (muted: boolean) => void;
    onLevelChange: (value: number) => Promise<boolean>;
    levelLabel: string;
    muteLabel?: string;
    disabled?: boolean;
    muteDisabled?: boolean;
    displayedValue?: string;
    showMute?: boolean;
    displayMode?: "gain" | "percent";
    maxGainDecibels?: number;
};

export function LevelControl({
    name,
    value,
    muted,
    onMuteChange,
    onLevelChange,
    levelLabel,
    muteLabel,
    disabled = false,
    muteDisabled = false,
    displayedValue,
    showMute = true,
    displayMode = "gain",
    maxGainDecibels = 0,
}: LevelControlProps) {
    const gainControl = displayMode === "gain";
    const min = gainControl ? MIN_GAIN_DECIBELS : 0;
    const max = gainControl ? maxGainDecibels : 1;
    const step = gainControl ? 0.5 : 0.01;
    const sliderValue = gainControl ? gainToDecibels(value) : value;
    const valueFormatter = gainControl
        ? formatGainDecibels
        : (current: number) => `${Math.round(current * 100)} percent`;
    return (
        <div className="mt-2 flex items-center gap-2">
            {showMute && (
                <button
                    type="button"
                    className="inline-flex min-h-7 min-w-7 shrink-0 items-center justify-center rounded-md text-slate-300 hover:bg-slate-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sky-300 disabled:opacity-40"
                    aria-label={
                        muteLabel ?? `${muted ? "Unmute" : "Mute"} ${name}`
                    }
                    aria-pressed={muted}
                    title={muteLabel ?? `${muted ? "Unmute" : "Mute"} ${name}`}
                    disabled={muteDisabled}
                    onClick={() => onMuteChange(!muted)}
                >
                    <FontAwesomeIcon
                        icon={muted ? faVolumeXmark : faVolumeHigh}
                    />
                </button>
            )}
            <StableRange
                value={sliderValue}
                label={levelLabel}
                disabled={disabled}
                min={min}
                max={max}
                step={step}
                formatValue={valueFormatter}
                onCommit={(next) =>
                    onLevelChange(gainControl ? decibelsToGain(next) : next)
                }
            />
            <span className="min-w-[4.5rem] shrink-0 text-right text-xs whitespace-nowrap text-slate-300 tabular-nums">
                {displayedValue ??
                    (gainControl
                        ? formatGainDecibels(sliderValue)
                        : `${Math.round(value * 100)}%`)}
            </span>
        </div>
    );
}
