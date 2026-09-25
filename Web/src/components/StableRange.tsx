import { useEffect, useRef, useState } from "react";

type StableRangeProps = {
    value: number;
    label: string;
    disabled?: boolean;
    min?: number;
    max?: number;
    step?: number;
    formatValue?: (value: number) => string;
    onCommit: (value: number) => Promise<boolean>;
};

export function StableRange({
    value,
    label,
    disabled = false,
    min = 0,
    max = 1,
    step = 0.01,
    formatValue = (current) => `${Math.round(current * 100)} percent`,
    onCommit,
}: StableRangeProps) {
    const [draft, setDraft] = useState(value);
    const interaction = useRef(false);
    const committedValue = useRef<number | null>(null);
    const latestValue = useRef<number | null>(null);
    const applying = useRef(false);

    useEffect(() => {
        if (
            interaction.current ||
            applying.current ||
            latestValue.current !== null
        )
            return;
        if (
            committedValue.current !== null &&
            Math.abs(value - committedValue.current) < 0.000001
        ) {
            committedValue.current = null;
        }
        if (committedValue.current === null) setDraft(value);
    }, [value]);

    const applyLatest = async () => {
        if (applying.current) return;
        applying.current = true;
        while (latestValue.current !== null) {
            const next = latestValue.current;
            latestValue.current = null;
            committedValue.current = next;
            if (!(await onCommit(next))) {
                committedValue.current = null;
                setDraft(value);
                latestValue.current = null;
                break;
            }
        }
        applying.current = false;
    };

    const requestApply = (next: number) => {
        if (committedValue.current === next && latestValue.current === null)
            return;
        latestValue.current = next;
        void applyLatest();
    };

    return (
        <input
            type="range"
            min={min}
            max={max}
            step={step}
            value={draft}
            aria-label={label}
            aria-valuetext={formatValue(draft)}
            disabled={disabled}
            onPointerDown={() => {
                interaction.current = true;
            }}
            onPointerUp={(event) => {
                interaction.current = false;
                requestApply(Number(event.currentTarget.value));
            }}
            onPointerCancel={() => {
                interaction.current = false;
                setDraft(value);
            }}
            onKeyDown={(event) => {
                if (
                    [
                        "ArrowLeft",
                        "ArrowRight",
                        "ArrowUp",
                        "ArrowDown",
                        "Home",
                        "End",
                        "PageUp",
                        "PageDown",
                    ].includes(event.key)
                ) {
                    interaction.current = true;
                }
            }}
            onKeyUp={(event) => {
                if (
                    [
                        "ArrowLeft",
                        "ArrowRight",
                        "ArrowUp",
                        "ArrowDown",
                        "Home",
                        "End",
                        "PageUp",
                        "PageDown",
                    ].includes(event.key)
                ) {
                    interaction.current = false;
                    requestApply(Number(event.currentTarget.value));
                }
            }}
            onBlur={(event) => {
                if (interaction.current) {
                    interaction.current = false;
                    requestApply(Number(event.currentTarget.value));
                }
            }}
            onChange={(event) => {
                const next = Number(event.currentTarget.value);
                interaction.current = true;
                setDraft(next);
                requestApply(next);
            }}
        />
    );
}
