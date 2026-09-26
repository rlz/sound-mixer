import { useEffect, useState } from "react";
import { faXmark } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { useMixerStore } from "./store";
import "./bridge";
import { AppHeader } from "./components/AppHeader";
import { MasterSwitch } from "./components/MasterSwitch";
import { DestinationSidebar } from "./components/DestinationSidebar";
import { InputsPanel } from "./components/InputsPanel";
import { MixEditorPanel } from "./components/MixEditorPanel";
import { useMixerCommand } from "./useMixerCommand";
import "./styles.css";

export function App() {
    const mixerState = useMixerStore((state) => state.mixerState);
    const setMixerState = useMixerStore((state) => state.setMixerState);
    const selectedItem = useMixerStore((state) => state.selectedItem);
    const setSelectedItem = useMixerStore((state) => state.setSelectedItem);
    const pending = useMixerStore((state) => state.pending);
    const commandError = useMixerStore((state) => state.commandError);
    const [notification, setNotification] = useState<string | null>(null);

    useEffect(() => {
        if (!window.soundMixerBridge) return;
        window.soundMixerBridge.onNotification = ({ message }) => {
            setNotification(message);
        };
    }, []);

    useEffect(() => {
        if (!notification) return;
        const timeout = window.setTimeout(() => setNotification(null), 5000);
        return () => window.clearTimeout(timeout);
    }, [notification]);

    const send = useMixerCommand();

    useEffect(() => {
        if (window.soundMixerBridge) {
            window.soundMixerBridge.onState = setMixerState;
            void window.soundMixerBridge
                .send({ command: "ready" })
                .catch((error: Error) => {
                    console.error("Could not request the native state:", error);
                });
        }
    }, [setMixerState]);

    useEffect(() => {
        if (selectedItem !== null || !mixerState) return;
        const firstDestination =
            mixerState.outputs.find((output) => output.available) ??
            mixerState.buses[0];
        if (!firstDestination) return;
        if ("uid" in firstDestination) {
            setSelectedItem(`output:${firstDestination.uid}`);
        } else {
            setSelectedItem(`bus:${firstDestination.id}`);
        }
    }, [mixerState, selectedItem, setSelectedItem]);

    return (
        <main className="flex h-dvh min-h-0 w-full flex-col overflow-hidden bg-slate-950 text-slate-100">
            {notification && (
                <div
                    className="fixed top-4 right-4 z-50 flex max-w-md items-start gap-3 rounded-lg border border-amber-700 bg-slate-900 px-4 py-3 text-sm text-amber-100 shadow-xl"
                    role="status"
                    aria-live="polite"
                >
                    <p className="flex-1">{notification}</p>
                    <button
                        type="button"
                        aria-label="Dismiss notification"
                        title="Dismiss notification"
                        className="flex h-6 w-6 shrink-0 items-center justify-center rounded text-amber-200 hover:bg-slate-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300"
                        onClick={() => setNotification(null)}
                    >
                        <FontAwesomeIcon icon={faXmark} aria-hidden="true" />
                    </button>
                </div>
            )}
            <section className="flex min-h-0 flex-1 flex-col">
                <div className="flex min-h-14 items-center justify-between gap-4 border-b border-slate-700 bg-slate-900 px-4 py-2">
                    <AppHeader />

                    <MasterSwitch
                        mixerState={mixerState}
                        pending={pending}
                        onToggle={() =>
                            mixerState &&
                            void send("master", {
                                command: "setMasterEnabled",
                                enabled: !mixerState.isEnabled,
                            })
                        }
                    />
                </div>

                {commandError && (
                    <p
                        className="border-b border-rose-800 bg-rose-950 px-5 py-2 text-sm text-rose-200"
                        role="alert"
                    >
                        {commandError}
                    </p>
                )}

                <div className="grid min-h-0 flex-1 grid-cols-3 overflow-hidden">
                    <DestinationSidebar />
                    <MixEditorPanel />
                    <InputsPanel />
                </div>
            </section>
        </main>
    );
}
