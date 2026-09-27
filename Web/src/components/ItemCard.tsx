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
    onChannelClick?: () => void;
    status?: "inactive" | "active" | "problem";
    statusLabel?: string;
    dimmed?: boolean;
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
    onChannelClick,
    status,
    statusLabel,
    dimmed = false,
    selectOnSurface = false,
    onSelect,
    leadingAction,
    trailingAction,
    children,
}: ItemCardProps) {
    const title =
        onSelect && !selectOnSurface ? (
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
                className="min-w-0 flex-1 truncate font-medium text-slate-100 select-text"
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
            className={`min-w-0 rounded-lg border px-3 py-2 text-sm select-text ${dimmed ? (selected ? "border-slate-500 bg-slate-900/40 ring-1 ring-slate-500" : "border-slate-700 bg-slate-900/40") : selected ? "border-sky-300 bg-sky-400/15 ring-1 ring-sky-300" : "border-slate-800 bg-slate-900/70"}`}
        >
            <div className="mb-1 flex min-w-0 items-center gap-2 text-[10px] text-slate-500">
                {leadingAction}
                <span
                    className={`min-w-0 flex-1 truncate ${dimmed ? "opacity-40" : ""}`}
                >
                    {type}
                </span>
                {channelCount !== undefined && onChannelClick && (
                    <button
                        type="button"
                        onClick={onChannelClick}
                        aria-label={`Configure ${name} channel routing, ${channelCount} input channels`}
                        title="Configure channel routing"
                        className={`shrink-0 rounded text-sky-200 underline decoration-dotted hover:text-sky-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 ${dimmed ? "opacity-40" : ""}`}
                    >
                        {channelCount} ch
                    </button>
                )}
                {channelCount !== undefined && !onChannelClick && (
                    <span
                        className={`shrink-0 ${dimmed ? "opacity-40" : ""}`}
                        aria-label={`${channelCount} channels`}
                    >
                        {channelCount} ch
                    </span>
                )}
                {trailingAction}
            </div>
            <div
                className={`flex min-w-0 items-center gap-2 ${dimmed ? "opacity-40" : ""}`}
            >
                <AvailabilityDot
                    label={statusLabel}
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
            <div className={dimmed ? "opacity-40" : undefined}>
                <PeakMeter level={level} label={levelLabel} />
                {children}
            </div>
        </article>
    );
}
