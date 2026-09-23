import type { MixerState } from "../types";

type Props = {
    mixerState: MixerState | null;
    pending: string | null;
    onToggle: () => void;
};

export function MasterSwitch({ mixerState, pending, onToggle }: Props) {
    return (
        <section className="mb-8 flex flex-wrap items-center justify-between gap-4 rounded-2xl border border-slate-800 bg-slate-900 px-5 py-4">
            <div>
                <h1 className="font-semibold">Mixing On/Off</h1>
                <p className="mt-1 text-sm text-slate-400" role="status">
                    {mixerState?.isEnabled
                        ? "Sound Mixer is outputting audio."
                        : "Sound Mixer is not currently outputting audio."}
                </p>
            </div>
            <button
                type="button"
                role="switch"
                aria-checked={mixerState?.isEnabled ?? false}
                aria-label="Mixing On/Off"
                disabled={!mixerState || pending !== null}
                onClick={onToggle}
                className={`rounded-full px-4 py-2 text-sm font-semibold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sky-300 disabled:opacity-50 ${mixerState?.isEnabled ? "bg-emerald-300 text-slate-950" : "bg-slate-700 text-slate-100"}`}
            >
                {mixerState?.isEnabled ? "On" : "Off"}
            </button>
        </section>
    );
}
