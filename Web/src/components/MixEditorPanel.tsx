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
    const routeDeviceUID = useMixerStore((state) => state.routeDeviceUID);
    const setRouteDeviceUID = useMixerStore((state) => state.setRouteDeviceUID);
    const [renameDialogOpen, setRenameDialogOpen] = useState(false);
    const send = useMixerCommand();

    const selectedOutput = mixerState?.outputs.find(
        (output) => selectedItem === `output:${output.uid}`,
    );
    const selectedBus = mixerState?.buses.find(
        (bus) => selectedItem === `bus:${bus.id}`,
    );
    const selectedRoute = mixerState?.blackHoleRoutes.find(
        (route) => selectedItem === `blackHole:${route.id}`,
    );
    const selectedTarget = selectedOutput
        ? { target: "output" as const, id: selectedOutput.uid }
        : selectedBus
          ? { target: "bus" as const, id: selectedBus.id }
          : selectedRoute
            ? { target: "route" as const, id: selectedRoute.id }
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
    const deleteVirtualItem = async (
        kind: "bus" | "route",
        id: string,
        name: string,
    ) => {
        const approved = window.confirm(
            kind === "route"
                ? `Delete “${name}” and its saved mix? This also removes it as a source from every mix that uses it.`
                : `Delete “${name}”? Mixes that use this bus will prevent deletion.`,
        );
        if (!approved) return;
        const accepted = await send(`${kind}-delete:${id}`, {
            command: kind === "route" ? "deleteRoute" : "deleteBus",
            id,
        });
        if (accepted) {
            setSelectedItem(null);
            setBusNameDraft(null);
        }
    };
    return (
        <>
            <div className="min-h-0 min-w-0 [scrollbar-gutter:stable] overflow-x-hidden overflow-y-auto overscroll-contain bg-slate-950 p-3.5">
                <div className="mb-6 flex items-start justify-between gap-4">
                    <div>
                        <h1 className="text-xl font-semibold tracking-tight">
                            {selectedOutput?.name ??
                                selectedBus?.name ??
                                selectedRoute?.name ??
                                "Settings"}
                        </h1>
                        <p className="mt-1 text-sm text-slate-400">
                            {selectedOutput
                                ? "System"
                                : selectedBus
                                  ? "Virtual"
                                  : selectedRoute
                                    ? "BlackHole"
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
                            {(selectedBus || selectedRoute) && (
                                <>
                                    <button
                                        type="button"
                                        disabled={pending !== null}
                                        aria-label={`Rename ${selectedBus?.name ?? selectedRoute?.name}`}
                                        title="Edit name"
                                        className="flex h-8 w-8 items-center justify-center rounded-md text-slate-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:opacity-50"
                                        onClick={() => {
                                            setBusNameDraft(
                                                selectedBus?.name ??
                                                    selectedRoute?.name ??
                                                    "",
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
                                        aria-label={`Delete ${selectedBus?.name ?? selectedRoute?.name}`}
                                        title="Delete"
                                        className="flex h-8 w-8 items-center justify-center rounded-md text-rose-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-rose-300 disabled:opacity-50"
                                        onClick={() => {
                                            if (selectedRoute)
                                                void deleteVirtualItem(
                                                    "route",
                                                    selectedRoute.id,
                                                    selectedRoute.name,
                                                );
                                            else if (selectedBus)
                                                void deleteVirtualItem(
                                                    "bus",
                                                    selectedBus.id,
                                                    selectedBus.name,
                                                );
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

                {selectedItem === "route:new" && (
                    <section
                        className="mb-5 rounded-2xl border border-slate-800 bg-slate-900 p-5"
                        aria-label="Virtual item settings"
                    >
                        <form
                            className="space-y-3"
                            onSubmit={(event) => {
                                event.preventDefault();
                                void send("route-create", {
                                    command: "createRoute",
                                    deviceUID: routeDeviceUID,
                                });
                            }}
                        >
                            <div className="grid gap-3 sm:grid-cols-2">
                                <label className="text-sm">
                                    BlackHole device
                                    <select
                                        required
                                        value={routeDeviceUID}
                                        onChange={(event) =>
                                            setRouteDeviceUID(
                                                event.currentTarget.value,
                                            )
                                        }
                                        className="mt-1 w-full rounded-lg border border-slate-600 bg-slate-950 px-3 py-2 text-slate-100"
                                    >
                                        <option value="">
                                            Choose an available device
                                        </option>
                                        {mixerState?.outputs
                                            .filter(
                                                (output) =>
                                                    output.isBlackHole &&
                                                    output.available,
                                            )
                                            .map((output) => (
                                                <option
                                                    key={output.uid}
                                                    value={output.uid}
                                                >
                                                    {output.name} ·{" "}
                                                    {output.outputChannels}{" "}
                                                    channels
                                                </option>
                                            ))}
                                    </select>
                                </label>
                            </div>
                            <p className="text-xs text-slate-400">
                                Sound Mixer assigns the lowest free adjacent
                                stereo pair and names the route from its
                                channels.
                            </p>
                            <button
                                type="submit"
                                disabled={pending !== null}
                                className="rounded-lg bg-sky-300 px-3 py-2 text-sm font-semibold text-slate-950 disabled:opacity-50"
                            >
                                Create route
                            </button>
                        </form>
                    </section>
                )}

                <MixSourceList />
            </div>

            <RenameDestinationDialog
                open={renameDialogOpen}
                send={send}
                onClose={() => setRenameDialogOpen(false)}
            />
        </>
    );
});
