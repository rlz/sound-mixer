import { useEffect, useRef } from "react";
import { PeakMeter } from "./PeakMeter";
import { StableRange } from "./StableRange";
import {
    decibelsToGain,
    formatGainDecibels,
    gainToDecibels,
} from "./audioGain";

type Props = {
    name: string;
    inputChannels: number;
    outputChannels: number;
    routing: number[][];
    channelLevels?: number[];
    channelsLinked?: boolean;
    meters?: (number | null)[];
    disabled: boolean;
    onClose: () => void;
    onRoutingChange: (routing: number[][]) => void;
    onGainChange?: (levels: number[], linked: boolean) => Promise<boolean>;
};

export function ChannelMatrixDialog({
    name,
    inputChannels,
    outputChannels,
    routing,
    channelLevels,
    channelsLinked = true,
    meters,
    disabled,
    onClose,
    onRoutingChange,
    onGainChange,
}: Props) {
    const closeRef = useRef<HTMLButtonElement>(null);
    useEffect(() => {
        const trigger = document.activeElement as HTMLElement | null;
        closeRef.current?.focus();
        return () => trigger?.focus();
    }, []);
    const rows = Array.from(
        { length: inputChannels },
        (_, index) => routing[index] ?? [],
    );
    const levels = rows.map((_, index) => channelLevels?.[index] ?? 1);
    const linkedLevel = Math.max(0, ...levels);
    const updateLevel = (index: number, decibels: number) => {
        const value = decibelsToGain(decibels);
        const next = [...levels];
        if (channelsLinked) {
            for (let channel = 0; channel < next.length; channel += 1) {
                next[channel] =
                    linkedLevel > 0
                        ? Math.min(1, (next[channel] * value) / linkedLevel)
                        : value;
            }
        } else {
            next[index] = value;
        }
        return onGainChange?.(next, channelsLinked) ?? Promise.resolve(false);
    };

    return (
        <div
            className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4"
            onMouseDown={(event) => {
                if (event.target === event.currentTarget) onClose();
            }}
        >
            <div
                role="dialog"
                aria-modal="true"
                aria-label={`${name} channel routing`}
                onKeyDown={(event) => {
                    if (event.key === "Escape") onClose();
                    if (event.key === "Tab") {
                        const controls =
                            event.currentTarget.querySelectorAll<HTMLElement>(
                                "button:not(:disabled), input:not(:disabled), [role='slider']:not([aria-disabled='true'])",
                            );
                        const first = controls.item(0);
                        const last = controls.item(controls.length - 1);
                        if (
                            event.shiftKey &&
                            document.activeElement === first
                        ) {
                            event.preventDefault();
                            last?.focus();
                        } else if (
                            !event.shiftKey &&
                            document.activeElement === last
                        ) {
                            event.preventDefault();
                            first?.focus();
                        }
                    }
                }}
                className="max-h-[90vh] max-w-[95vw] overflow-auto rounded-lg border border-slate-700 bg-slate-950 p-4 text-sm text-slate-100 shadow-xl"
            >
                <div className="mb-3 flex items-center justify-between gap-4">
                    <h2 className="font-semibold">{name} channel routing</h2>
                    <button
                        ref={closeRef}
                        type="button"
                        onClick={onClose}
                        className="rounded border border-slate-600 px-2 py-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300"
                    >
                        Close
                    </button>
                </div>
                <p className="mb-3 text-xs text-slate-400">
                    Select every output channel that should receive each input
                    channel.
                </p>
                <table className="border-separate border-spacing-1 text-xs">
                    <thead>
                        <tr>
                            <th scope="col" className="px-2 text-left">
                                Input
                            </th>
                            {Array.from(
                                { length: outputChannels },
                                (_, output) => (
                                    <th
                                        scope="col"
                                        key={output}
                                        className="min-w-12 px-1 text-center"
                                    >
                                        Out {output + 1}
                                    </th>
                                ),
                            )}
                        </tr>
                    </thead>
                    <tbody>
                        {rows.map((selected, input) => (
                            <tr key={input}>
                                <th
                                    scope="row"
                                    className="min-w-28 pr-2 text-left font-normal"
                                >
                                    In {input + 1}
                                    {meters && (
                                        <PeakMeter
                                            level={meters[input]}
                                            label={`${name} input channel ${input + 1}`}
                                        />
                                    )}
                                </th>
                                {Array.from(
                                    { length: outputChannels },
                                    (_, output) => {
                                        const active = selected.includes(
                                            output + 1,
                                        );
                                        return (
                                            <td
                                                key={output}
                                                className="text-center"
                                            >
                                                <button
                                                    type="button"
                                                    disabled={disabled}
                                                    aria-pressed={active}
                                                    aria-label={`Input ${input + 1} to output ${output + 1}`}
                                                    onClick={() => {
                                                        const next = rows.map(
                                                            (row) => [...row],
                                                        );
                                                        next[input] = active
                                                            ? next[
                                                                  input
                                                              ].filter(
                                                                  (channel) =>
                                                                      channel !==
                                                                      output +
                                                                          1,
                                                              )
                                                            : [
                                                                  ...next[
                                                                      input
                                                                  ],
                                                                  output + 1,
                                                              ].sort(
                                                                  (a, b) =>
                                                                      a - b,
                                                              );
                                                        onRoutingChange(next);
                                                    }}
                                                    className={`h-8 w-8 rounded border focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 ${active ? "border-sky-300 bg-sky-500 text-slate-950" : "border-slate-600 bg-slate-900 hover:bg-slate-800"}`}
                                                >
                                                    {active ? "✓" : "·"}
                                                </button>
                                            </td>
                                        );
                                    },
                                )}
                            </tr>
                        ))}
                    </tbody>
                </table>
                {onGainChange && (
                    <div className="mt-4 space-y-2 border-t border-slate-700 pt-3">
                        <label className="flex items-center gap-2 text-xs">
                            <input
                                type="checkbox"
                                checked={channelsLinked}
                                disabled={disabled}
                                onChange={(event) =>
                                    onGainChange(
                                        levels,
                                        event.currentTarget.checked,
                                    )
                                }
                            />
                            Link channel gains
                        </label>
                        {levels.map((level, index) => (
                            <div
                                key={index}
                                className="flex items-center gap-3 text-xs"
                            >
                                <span className="w-12 shrink-0">
                                    In {index + 1}
                                </span>
                                <StableRange
                                    value={gainToDecibels(
                                        channelsLinked ? linkedLevel : level,
                                    )}
                                    label={`${name} channel ${index + 1} gain`}
                                    disabled={
                                        disabled ||
                                        (channelsLinked && index > 0)
                                    }
                                    onCommit={(value) =>
                                        updateLevel(index, value)
                                    }
                                    min={-60}
                                    max={0}
                                    step={0.5}
                                    formatValue={formatGainDecibels}
                                />
                                <span>
                                    {formatGainDecibels(gainToDecibels(level))}
                                </span>
                            </div>
                        ))}
                    </div>
                )}
            </div>
        </div>
    );
}
