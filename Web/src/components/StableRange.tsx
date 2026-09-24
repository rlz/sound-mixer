import { useEffect, useRef, useState } from "react";

type StableRangeProps = {
    value: number;
    label: string;
    disabled?: boolean;
    onCommit: (value: number) => Promise<boolean>;
};

export function StableRange({
    value,
    label,
    disabled = false,
    onCommit,
}: StableRangeProps) {
    const [draft, setDraft] = useState(value);
    const interaction = useRef(false);
    const committedValue = useRef<number | null>(null);

    useEffect(() => {
        if (interaction.current) return;
        if (
            committedValue.current !== null &&
            Math.abs(value - committedValue.current) < 0.000001
        ) {
            committedValue.current = null;
        }
        if (committedValue.current === null) setDraft(value);
    }, [value]);

    const commit = async (next: number) => {
        interaction.current = false;
        committedValue.current = next;
        setDraft(next);
        if (!(await onCommit(next))) {
            committedValue.current = null;
            setDraft(value);
        }
    };

    return (
        <input
            type="range"
            min="0"
            max="1"
            step="0.01"
            value={draft}
            aria-label={label}
            aria-valuetext={`${Math.round(draft * 100)} percent`}
            disabled={disabled}
            onPointerDown={() => {
                interaction.current = true;
            }}
            onPointerUp={(event) => {
                void commit(Number(event.currentTarget.value));
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
                    void commit(Number(event.currentTarget.value));
                }
            }}
            onBlur={(event) => {
                if (interaction.current) {
                    void commit(Number(event.currentTarget.value));
                }
            }}
            onChange={(event) => setDraft(Number(event.currentTarget.value))}
        />
    );
}
