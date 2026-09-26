import type { ReactNode } from "react";
import { AvailabilityDot } from "./AvailabilityDot";
import { PeakMeter } from "./PeakMeter";

type ItemCardProps = {
    name: string;
    type: string;
    level: number | null | undefined;
    levelLabel: string;
    available?: boolean;
    selected?: boolean;
    channelCount?: number;
    status?: "inactive" | "active" | "problem";
    onSelect?: () => void;
    leadingAction?: ReactNode;
    trailingAction?: ReactNode;
    children?: ReactNode;
};

export function ItemCard({
    name,
    type,
    level,
    levelLabel,
    available,
    selected = false,
    channelCount,
    status,
    onSelect,
    leadingAction,
    trailingAction,
    children,
}: ItemCardProps) {
    const title = onSelect ? (
        <button
            type="button"
            aria-current={selected ? "true" : undefined}
            onClick={onSelect}
            className="min-w-0 flex-1 truncate text-left font-medium text-slate-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300"
            title={name}
        >
            {name}
        </button>
    ) : (
        <span className="min-w-0 flex-1 truncate font-medium" title={name}>
            {name}
        </span>
    );

    return (
        <article
            className={`min-w-0 rounded-lg border px-3 py-2 text-sm ${selected ? "border-sky-300 bg-sky-400/15 ring-1 ring-sky-300" : "border-slate-800 bg-slate-900/70"}`}
        >
            <div className="flex min-w-0 items-center gap-2">
                {leadingAction}
                <AvailabilityDot
                    status={
                        status ??
                        (available === false
                            ? "problem"
                            : typeof level === "number" && level > 0
                              ? "active"
                              : "inactive")
                    }
                />
                {title}
                {channelCount !== undefined && (
                    <span
                        className="shrink-0 text-[10px] text-slate-500"
                        aria-label={`${channelCount} channels`}
                    >
                        {channelCount} ch
                    </span>
                )}
                {trailingAction}
            </div>
            <p className="mt-1 text-[10px] text-slate-500">{type}</p>
            <PeakMeter level={level} label={levelLabel} />
            {children}
        </article>
    );
}
