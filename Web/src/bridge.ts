import type { MixerState } from "./types";

const requestCallbacks = new Map<
    string,
    (accepted: boolean, error?: string) => void
>();

window.soundMixerBridge = {
    onState: () => undefined,
    onCommandResult: ({ requestId, accepted, error }) => {
        requestCallbacks.get(requestId)?.(accepted, error);
        requestCallbacks.delete(requestId);
    },
    send: (command) =>
        new Promise((resolve, reject) => {
            const requestId = crypto.randomUUID();
            requestCallbacks.set(requestId, (accepted, error) => {
                if (accepted) resolve();
                else reject(new Error(error ?? "Native command was rejected."));
            });
            if (!window.webkit) {
                requestCallbacks.delete(requestId);
                reject(
                    new Error(
                        "The native bridge is only available in the app.",
                    ),
                );
                return;
            }
            window.webkit.messageHandlers.soundMixer.postMessage({
                ...command,
                requestId,
            });
        }),
};

export function receiveNativeState(state: MixerState) {
    window.soundMixerBridge?.onState(state);
}
