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
    selectOnSurface?: boolean;
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
    selectOnSurface = false,
    onSelect,
    leadingAction,
    trailingAction,
    children,
}: ItemCardProps) {
    const title = onSelect && !selectOnSurface ? (
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
        <span
            className="min-w-0 flex-1 select-text truncate font-medium text-slate-100"
            title={name}
        >
            {name}
        </span>
    );

    return (
        <article
            onClick={(event) => {
                if (!selectOnSurface || !onSelect) return;
                if (window.getSelection()?.toString()) return;
                const target = event.target;
                if (
                    target instanceof Element &&
                    target.closest(
                        "button, input, select, textarea, a, [role='slider']",
                    )
                ) {
                    return;
                }
                onSelect();
            }}
            className={`min-w-0 select-text rounded-lg border px-3 py-2 text-sm ${selected ? "border-sky-300 bg-sky-400/15 ring-1 ring-sky-300" : "border-slate-800 bg-slate-900/70"}`}
        >
            <div className="mb-1 flex min-w-0 items-center gap-2 text-[10px] text-slate-500">
                {leadingAction}
                <span className="min-w-0 flex-1 truncate">{type}</span>
                {channelCount !== undefined && (
                    <span
                        className="shrink-0"
                        aria-label={`${channelCount} channels`}
                    >
                        {channelCount} ch
                    </span>
                )}
                {trailingAction}
            </div>
            <div className="flex min-w-0 items-center gap-2">
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
            </div>
            <PeakMeter level={level} label={levelLabel} />
            {children}
        </article>
    );
}
