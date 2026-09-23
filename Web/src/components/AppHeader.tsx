import { faSliders } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";

export function AppHeader() {
    return (
        <header className="mb-10 flex items-center gap-3">
            <div
                aria-hidden="true"
                className="flex h-10 w-10 items-center justify-center rounded-xl bg-sky-400 text-slate-950"
            >
                <FontAwesomeIcon icon={faSliders} />
            </div>
            <span className="text-sm font-semibold uppercase tracking-[0.18em] text-sky-300">
                Sound Mixer
            </span>
        </header>
    );
}
