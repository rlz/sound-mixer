import { useState } from "react";
import { useMixerStore } from "../store";
import type { BridgeCommand } from "../types";
import { DialogShell } from "./DialogShell";

type DialogProps = {
    send: (key: string, command: BridgeCommand) => Promise<boolean>;
};

export function ApplicationCatalogDialog({
    send,
    onClose,
}: DialogProps & { onClose: () => void }) {
    const [search, setSearch] = useState("");
    const applications =
        useMixerStore((state) => state.mixerState?.applications) ?? [];
    const pending = useMixerStore((state) => state.pending);
    const registered = new Set(
        applications.filter((item) => item.registered).map((item) => item.id),
    );
    const available = applications
        .filter((item) => item.available && !registered.has(item.id))
        .filter((item) =>
            `${item.name} ${item.id}`
                .toLocaleLowerCase()
                .includes(search.trim().toLocaleLowerCase()),
        );

    return (
        <DialogShell
            title="Add an application"
            labelledBy="application-catalog-title"
            onClose={onClose}
        >
            <label className="mt-3 block text-sm">
                Search running applications
                <input
                    autoFocus
                    type="search"
                    value={search}
                    onChange={(event) => setSearch(event.currentTarget.value)}
                    placeholder="Name or bundle identifier"
                    className="mt-1 w-full rounded-lg border border-slate-600 bg-slate-950 px-3 py-2 text-slate-100 placeholder:text-slate-500"
                />
            </label>
            <ul className="mt-3 max-h-72 space-y-2 overflow-y-auto">
                {available.map((application) => (
                    <li
                        key={application.id}
                        className="flex items-center justify-between gap-3 rounded-lg border border-slate-800 px-3 py-2"
                    >
                        <span className="min-w-0">
                            <span className="block truncate text-sm">
                                {application.name}
                            </span>
                            <span className="block truncate text-xs text-slate-400">
                                {application.id}
                            </span>
                        </span>
                        <button
                            type="button"
                            disabled={pending !== null}
                            className="shrink-0 rounded bg-sky-300 px-3 py-1.5 text-sm font-semibold text-slate-950 disabled:opacity-50"
                            onClick={() => {
                                void send(`app-register:${application.id}`, {
                                    command: "addApplicationInput",
                                    applicationID: application.id,
                                });
                                onClose();
                            }}
                        >
                            Add input
                        </button>
                    </li>
                ))}
                {available.length === 0 && (
                    <li className="px-2 py-4 text-sm text-slate-400">
                        {applications.some(
                            (item) =>
                                item.available && !registered.has(item.id),
                        )
                            ? "No applications match this search."
                            : "No eligible running applications are available."}
                    </li>
                )}
            </ul>
        </DialogShell>
    );
}

export function RenameDestinationDialog({
    open,
    send,
    onClose,
}: DialogProps & { open: boolean; onClose: () => void }) {
    const selectedItem = useMixerStore((state) => state.selectedItem);
    const buses = useMixerStore((state) => state.mixerState?.buses) ?? [];
    const pending = useMixerStore((state) => state.pending);
    const draft = useMixerStore((state) => state.busNameDraft);
    const setDraft = useMixerStore((state) => state.setBusNameDraft);
    const bus = buses.find((item) => selectedItem === `bus:${item.id}`);

    if (!open || !bus) return null;
    return (
        <DialogShell
            title="Rename virtual bus"
            labelledBy="rename-destination-title"
            onClose={onClose}
            className="w-full max-w-md"
        >
            <form
                onSubmit={async (event) => {
                    event.preventDefault();
                    const success = await send("bus-rename", {
                        command: "renameBus",
                        id: bus.id,
                        name: draft ?? "",
                    });
                    if (success) onClose();
                }}
            >
                <label
                    className="mt-3 block text-sm"
                    htmlFor="rename-destination-input"
                >
                    Name
                    <input
                        autoFocus
                        id="rename-destination-input"
                        maxLength={64}
                        required
                        value={draft ?? ""}
                        onChange={(event) =>
                            setDraft(event.currentTarget.value)
                        }
                        className="mt-1 w-full rounded-lg border border-slate-600 bg-slate-950 px-3 py-2 text-slate-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300"
                    />
                </label>
                <div className="mt-4 flex justify-end gap-2">
                    <button
                        type="button"
                        onClick={onClose}
                        className="rounded-lg border border-slate-700 px-3 py-2 text-sm text-slate-200"
                    >
                        Cancel
                    </button>
                    <button
                        type="submit"
                        disabled={pending !== null}
                        className="rounded-lg bg-sky-300 px-3 py-2 text-sm font-semibold text-slate-950 disabled:opacity-50"
                    >
                        Save name
                    </button>
                </div>
            </form>
        </DialogShell>
    );
}
