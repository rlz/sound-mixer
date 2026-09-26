import { useCallback } from "react";
import { useMixerStore } from "./store";
import type { BridgeCommand } from "./types";

export function useMixerCommand() {
    return useCallback(
        async (
            key: string,
            command: BridgeCommand,
            rollback?: () => void,
            concurrent = false,
        ): Promise<boolean> => {
            const store = useMixerStore.getState();
            if (!window.soundMixerBridge || (!concurrent && store.pending)) {
                return false;
            }
            if (!concurrent) store.setPending(key);
            store.setCommandError(null);
            try {
                await window.soundMixerBridge.send(command);
                return true;
            } catch (error) {
                rollback?.();
                useMixerStore
                    .getState()
                    .setCommandError(
                        error instanceof Error
                            ? error.message
                            : "The change could not be saved.",
                    );
                return false;
            } finally {
                if (!concurrent) useMixerStore.getState().setPending(null);
            }
        },
        [],
    );
}
