import soundMixerMark from "../assets/sound-mixer-mark.svg";

export function AppHeader() {
    return (
        <header className="flex shrink-0 items-center gap-3 text-slate-100">
            <div
                aria-hidden="true"
                className="flex h-9 w-9 items-center justify-center rounded-lg bg-sky-400 text-slate-950"
            >
                <img alt="" className="h-5 w-5" src={soundMixerMark} />
            </div>
            <span className="text-sm font-semibold tracking-[0.18em] text-sky-300 uppercase">
                Rlz Sound Mixer
            </span>
        </header>
    );
}
