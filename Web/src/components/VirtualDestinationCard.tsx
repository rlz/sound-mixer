import { AvailabilityDot } from "./AvailabilityDot";
import { PeakMeter } from "./PeakMeter";
import { StableRange } from "./StableRange";

type VirtualDestinationCardProps = {
    name: string;
    kind: "bus" | "BlackHole route";
    available?: boolean;
    selected: boolean;
    gain: number;
    level: number | null;
    captureState?: string;
    onSelect: () => void;
    onGainChange: (gain: number) => Promise<boolean>;
};

export function VirtualDestinationCard({
    name,
    kind,
    available,
    selected,
    gain,
    level,
    captureState,
    onSelect,
    onGainChange,
}: VirtualDestinationCardProps) {
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
                {available !== undefined && (
                    <AvailabilityDot available={available} />
                )}
                <span className="min-w-0 truncate font-medium" title={name}>
                    {name}
                </span>
            </button>
            <p className="mt-1 text-[10px] text-slate-500">
                {kind === "bus" ? "Mix output" : "Output pair"}
            </p>
            <PeakMeter
                level={level}
                label={`${name} ${kind === "bus" ? "mix output" : "device output pair"}`}
            />
            {captureState?.startsWith("unavailable:") && (
                <p className="mt-1 text-xs text-amber-300" role="status">
                    {captureState.slice("unavailable:".length).trim()}
                </p>
            )}
            {captureState === "permissionDenied" && (
                <p className="mt-1 text-xs text-amber-300" role="status">
                    Input capture permission denied.
                </p>
            )}
            <div className="mt-2 flex items-center justify-between text-xs text-slate-300">
                <span>Mix gain</span>
                <span className="tabular-nums">{Math.round(gain * 100)}%</span>
            </div>
            <div className="mt-1 flex">
                <StableRange
                    value={gain}
                    label={`${name} ${kind} mix gain`}
                    onCommit={onGainChange}
                />
            </div>
        </div>
    );
}
