import { useEffect, useRef, useState } from "react";

type StableRangeProps = {
    value: number;
    label: string;
    title?: string;
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
    title,
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
    const confirmedValue = useRef(value);
    confirmedValue.current = value;

    useEffect(() => {
        if (
            interaction.current ||
            applying.current ||
            latestValue.current !== null
        )
            return;
        // Core Audio may report a rounded value, so an exact match with the
        // requested value cannot be required before following native updates.
        committedValue.current = null;
        setDraft(value);
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
                setDraft(confirmedValue.current);
                latestValue.current = null;
                break;
            }
        }
        applying.current = false;
        if (!interaction.current) {
            committedValue.current = null;
            setDraft(confirmedValue.current);
        }
    };

    const requestApply = (next: number) => {
        if (committedValue.current === next && latestValue.current === null) {
            if (!interaction.current && !applying.current) {
                committedValue.current = null;
                setDraft(confirmedValue.current);
            }
            return;
        }
        latestValue.current = next;
        void applyLatest();
    };

    return (
        <input
            type="range"
            className="min-w-0 flex-1"
            min={min}
            max={max}
            step={step}
            value={draft}
            aria-label={label}
            title={title}
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
                setDraft(confirmedValue.current);
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
                setDraft(next);
                requestApply(next);
            }}
        />
    );
}
