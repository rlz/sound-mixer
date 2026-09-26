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
    const matrixColumns = `360px repeat(${outputChannels}, 48px)`;
    const updateLevel = (index: number, decibels: number) => {
        const value = decibelsToGain(decibels);
        const next = [...levels];
        next[index] = value;
        return onGainChange?.(next) ?? Promise.resolve(false);
    };

    return (
        <DialogShell
            title="Chanel Routing"
            labelledBy="channel-routing-title"
            onClose={onClose}
            className="w-[min(1100px,95vw)] max-w-[95vw]"
            bodyClassName="text-sm !pb-0"
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
            <div className="-mx-4 overflow-x-auto px-4 text-xs">
                <div className="w-max space-y-px">
                    <div
                        className="grid gap-px"
                        style={{ gridTemplateColumns: matrixColumns }}
                    >
                        <span className="flex items-center px-2">Input</span>
                        <span
                            className="flex items-center justify-start"
                            style={{ gridColumn: `span ${outputChannels}` }}
                        >
                            Out
                        </span>
                    </div>
                    <div
                        className="grid gap-px"
                        style={{ gridTemplateColumns: matrixColumns }}
                    >
                        <span aria-hidden="true" />
                        {Array.from({ length: outputChannels }, (_, output) => (
                            <span
                                key={output}
                                className="flex size-12 items-center justify-center"
                            >
                                {output + 1}
                            </span>
                        ))}
                    </div>
                    <div className="space-y-px">
                        {rows.map((selected, input) => (
                            <div
                                key={input}
                                className="grid gap-px"
                                style={{ gridTemplateColumns: matrixColumns }}
                            >
                                <div className="flex h-12 items-center gap-2 px-2">
                                    <span className="w-6 shrink-0 text-center font-medium tabular-nums">
                                        {input + 1}
                                    </span>
                                    <span className="flex min-w-0 flex-1 flex-col justify-center gap-1">
                                        {meters && (
                                            <PeakMeter
                                                level={meters[input]}
                                                label={`${name} input channel ${input + 1}`}
                                                className="mt-0 w-full"
                                            />
                                        )}
                                        {onGainChange && (
                                            <span className="flex min-w-0 items-center gap-2 whitespace-nowrap">
                                                <StableRange
                                                    value={gainToDecibels(
                                                        levels[input],
                                                    )}
                                                    label={`${name} channel ${input + 1} gain`}
                                                    disabled={gainDisabled}
                                                    onCommit={(value) =>
                                                        updateLevel(
                                                            input,
                                                            value,
                                                        )
                                                    }
                                                    min={-60}
                                                    max={0}
                                                    step={0.5}
                                                    formatValue={
                                                        formatGainDecibels
                                                    }
                                                />
                                                <span className="w-12 shrink-0 text-right whitespace-nowrap tabular-nums">
                                                    {formatGainDecibels(
                                                        gainToDecibels(
                                                            levels[input],
                                                        ),
                                                    )}
                                                </span>
                                            </span>
                                        )}
                                    </span>
                                </div>
                                {Array.from(
                                    { length: outputChannels },
                                    (_, output) => {
                                        const active = selected.includes(
                                            output + 1,
                                        );
                                        return (
                                            <button
                                                key={output}
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
                                                className={`size-12 rounded-none border focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 ${active ? "border-sky-300 bg-sky-500 text-slate-950" : "border-slate-600 bg-slate-900 hover:bg-slate-800"}`}
                                            >
                                                {active ? "✓" : "·"}
                                            </button>
                                        );
                                    },
                                )}
                            </div>
                        ))}
                    </div>
                    <div aria-hidden="true" className="h-8" />
                </div>
            </div>
        </DialogShell>
    );
}
