import type { MixerState } from "../types";

type Props = {
    mixerState: MixerState | null;
    pending: string | null;
    onToggle: () => void;
};

export function MasterSwitch({ mixerState, pending, onToggle }: Props) {
    return (
        <section className="flex min-w-0 items-center gap-4">
            <button
                type="button"
                role="switch"
                aria-checked={mixerState?.isEnabled ?? false}
                aria-label="Enable mixing"
                disabled={!mixerState || pending !== null}
                onClick={onToggle}
                className={`shrink-0 rounded-full px-4 py-2 text-sm font-semibold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sky-300 disabled:opacity-50 ${mixerState?.isEnabled ? "bg-emerald-300 text-slate-950" : "bg-slate-700 text-slate-100"}`}
            >
                {mixerState?.isEnabled ? "On" : "Off"}
            </button>
        </section>
    );
}
