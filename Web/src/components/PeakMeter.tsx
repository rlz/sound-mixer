type PeakMeterProps = {
    level: number | null | undefined;
    label: string;
};

export function PeakMeter({ level, label }: PeakMeterProps) {
    const active = typeof level === "number" && Number.isFinite(level);
    const peak = active ? Math.min(Math.max(level, 0), 1) : 0;
    const decibels = peak === 0 ? "−∞" : (20 * Math.log10(peak)).toFixed(1);
    const description = active ? `${decibels} dBFS` : "Inactive";
    const visualLevel =
        peak === 0 ? 0 : Math.max(0.02, (20 * Math.log10(peak) + 60) / 60);

    return (
        <div
            className="mt-2 flex items-center gap-2 text-xs text-slate-400"
            role="meter"
            aria-label={`${label} signal level`}
            aria-valuemin={0}
            aria-valuemax={1}
            aria-valuenow={peak}
            aria-valuetext={description}
        >
            <span
                aria-hidden="true"
                className="h-1.5 min-w-12 flex-1 overflow-hidden rounded bg-slate-700"
            >
                <span
                    className="block h-full rounded bg-emerald-400 transition-[width] duration-75"
                    style={{ width: `${visualLevel * 100}%` }}
                />
            </span>
            <span className="w-20 shrink-0 whitespace-nowrap text-right tabular-nums">
                {description}
            </span>
        </div>
    );
}
