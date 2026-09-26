import { memo, useState } from "react";
import {
    faArrowRotateLeft,
    faPen,
    faTrashCan,
} from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { useMixerStore } from "../store";
import { useMixerCommand } from "../useMixerCommand";
import { MixSourceList } from "./MixSourceList";
import { RenameDestinationDialog } from "./DestinationDialogs";
import type { MixState } from "../types";

export const MixEditorPanel = memo(function MixEditorPanel() {
    const mixerState = useMixerStore((state) => state.mixerState);
    const selectedItem = useMixerStore((state) => state.selectedItem);
    const setSelectedItem = useMixerStore((state) => state.setSelectedItem);
    const pending = useMixerStore((state) => state.pending);
    const setBusNameDraft = useMixerStore((state) => state.setBusNameDraft);
    const [renameDialogOpen, setRenameDialogOpen] = useState(false);
    const send = useMixerCommand();

    const selectedOutput = mixerState?.outputs.find(
        (output) => selectedItem === `output:${output.uid}`,
    );
    const selectedBus = mixerState?.buses.find(
        (bus) => selectedItem === `bus:${bus.id}`,
    );
    const selectedTarget = selectedOutput
        ? { target: "output" as const, id: selectedOutput.uid }
        : selectedBus
          ? { target: "bus" as const, id: selectedBus.id }
          : null;
    const selectedMix: MixState | null = selectedTarget
        ? (mixerState?.mixes.find(
              (mix) =>
                  mix.target === selectedTarget.target &&
                  mix.id === selectedTarget.id,
          ) ?? {
              ...selectedTarget,
              level: 1,
              inputs: [],
              levelReading: null,
          })
        : null;
    return (
        <>
            <section className="flex min-h-0 min-w-0 flex-col bg-slate-950">
                <h2 className="shrink-0 border-b border-slate-700 bg-slate-900 px-3.5 py-3 text-sm font-semibold">
                    Mix
                </h2>
                <div className="min-h-0 flex-1 [scrollbar-gutter:stable] overflow-x-hidden overflow-y-auto overscroll-contain p-3.5">
                    <div className="mb-6 flex items-start justify-between gap-4">
                        <div>
                            <h1 className="text-xl font-semibold tracking-tight">
                                {selectedOutput?.name ??
                                    selectedBus?.name ??
                                    "Settings"}
                            </h1>
                            <p className="mt-1 text-sm text-slate-400">
                                {selectedOutput
                                    ? "System"
                                    : selectedBus
                                      ? "Virtual"
                                      : "Select an output or virtual item."}
                            </p>
                        </div>
                        {selectedTarget && selectedMix && (
                            <div className="flex shrink-0 items-center gap-1">
                                <button
                                    type="button"
                                    disabled={
                                        pending !== null ||
                                        (selectedMix.inputs.length === 0 &&
                                            selectedMix.level === 1)
                                    }
                                    aria-label="Reset mix settings"
                                    title="Reset mix settings"
                                    className="flex h-8 w-8 items-center justify-center rounded-md text-slate-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:opacity-40"
                                    onClick={() =>
                                        void send(
                                            `mix-reset:${selectedTarget.id}`,
                                            {
                                                command: "resetMix",
                                                ...selectedTarget,
                                            },
                                        )
                                    }
                                >
                                    <FontAwesomeIcon
                                        icon={faArrowRotateLeft}
                                        aria-hidden="true"
                                    />
                                </button>
                                {selectedBus && (
                                    <>
                                        <button
                                            type="button"
                                            disabled={pending !== null}
                                            aria-label={`Rename ${selectedBus.name}`}
                                            title="Edit name"
                                            className="flex h-8 w-8 items-center justify-center rounded-md text-slate-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:opacity-50"
                                            onClick={() => {
                                                setBusNameDraft(
                                                    selectedBus.name,
                                                );
                                                setRenameDialogOpen(true);
                                            }}
                                        >
                                            <FontAwesomeIcon
                                                icon={faPen}
                                                aria-hidden="true"
                                            />
                                        </button>
                                        <button
                                            type="button"
                                            disabled={pending !== null}
                                            aria-label={`Delete ${selectedBus.name}`}
                                            title="Delete"
                                            className="flex h-8 w-8 items-center justify-center rounded-md text-rose-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-rose-300 disabled:opacity-50"
                                            onClick={() => {
                                                void send(
                                                    `bus-delete:${selectedBus.id}`,
                                                    {
                                                        command: "deleteBus",
                                                        id: selectedBus.id,
                                                    },
                                                ).then((accepted) => {
                                                    if (accepted) {
                                                        setSelectedItem(null);
                                                        setBusNameDraft(null);
                                                    }
                                                });
                                            }}
                                        >
                                            <FontAwesomeIcon
                                                icon={faTrashCan}
                                                aria-hidden="true"
                                            />
                                        </button>
                                    </>
                                )}
                            </div>
                        )}
                    </div>

                    <MixSourceList />
                </div>
            </section>

            <RenameDestinationDialog
                open={renameDialogOpen}
                send={send}
                onClose={() => setRenameDialogOpen(false)}
            />
        </>
    );
});
