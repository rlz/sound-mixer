import { PeakMeter } from "./PeakMeter";
import { StableRange } from "./StableRange";
import { DialogShell } from "./DialogShell";
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
    meters?: (number | null)[];
    disabled: boolean;
    gainDisabled?: boolean;
    onClose: () => void;
    onRoutingChange: (routing: number[][]) => void;
    onGainChange?: (levels: number[]) => Promise<boolean>;
};

export function ChannelMatrixDialog({
    name,
    inputChannels,
    outputChannels,
    routing,
    channelLevels,
    meters,
    disabled,
    gainDisabled = disabled,
    onClose,
    onRoutingChange,
    onGainChange,
}: Props) {
    const rows = Array.from(
        { length: inputChannels },
        (_, index) => routing[index] ?? [],
    );
    const levels = rows.map((_, index) => channelLevels?.[index] ?? 1);
    const updateLevel = (index: number, decibels: number) => {
        const value = decibelsToGain(decibels);
        const next = [...levels];
        next[index] = value;
        return onGainChange?.(next) ?? Promise.resolve(false);
    };

    return (
        <DialogShell
            title="channel routing"
            labelledBy="channel-routing-title"
            onClose={onClose}
            className="max-w-[95vw]"
            bodyClassName="text-sm"
            onDialogKeyDown={(event) => {
                if (event.key === "Tab") {
                    const controls =
                        event.currentTarget.querySelectorAll<HTMLElement>(
                            "button:not(:disabled), input:not(:disabled), [role='slider']:not([aria-disabled='true'])",
                        );
                    const first = controls.item(0);
                    const last = controls.item(controls.length - 1);
                    if (event.shiftKey && document.activeElement === first) {
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
        >
            <table className="border-separate border-spacing-1 text-xs">
                <thead>
                    <tr>
                        <th scope="col" className="px-2 text-left">
                            Input
                        </th>
                        <th
                            scope="colgroup"
                            colSpan={outputChannels}
                            className="pb-1 text-center"
                        >
                            Out
                        </th>
                    </tr>
                    <tr>
                        <th aria-hidden="true" />
                        {Array.from({ length: outputChannels }, (_, output) => (
                            <th
                                scope="col"
                                key={output}
                                className="min-w-16 px-2 text-center"
                            >
                                {output + 1}
                            </th>
                        ))}
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
                                                        ? next[input].filter(
                                                              (channel) =>
                                                                  channel !==
                                                                  output + 1,
                                                          )
                                                        : [
                                                              ...next[input],
                                                              output + 1,
                                                          ].sort(
                                                              (a, b) => a - b,
                                                          );
                                                    onRoutingChange(next);
                                                }}
                                                className={`h-8 w-12 rounded border focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 ${active ? "border-sky-300 bg-sky-500 text-slate-950" : "border-slate-600 bg-slate-900 hover:bg-slate-800"}`}
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
                    <h3 className="text-xs font-medium text-slate-300">
                        Channel gain
                    </h3>
                    {levels.map((level, index) => (
                        <div
                            key={index}
                            className="flex items-center gap-3 text-xs"
                        >
                            <span className="w-20 shrink-0">
                                In {index + 1} gain
                            </span>
                            <StableRange
                                value={gainToDecibels(level)}
                                label={`${name} channel ${index + 1} gain`}
                                disabled={gainDisabled}
                                onCommit={(value) => updateLevel(index, value)}
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
        </DialogShell>
    );
}
