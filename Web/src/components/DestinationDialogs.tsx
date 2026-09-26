import { useMixerStore } from "../store";
import type { BridgeCommand } from "../types";
import { DialogShell } from "./DialogShell";

type DialogProps = {
    send: (key: string, command: BridgeCommand) => Promise<boolean>;
};

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
