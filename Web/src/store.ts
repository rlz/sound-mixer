import { create } from "zustand";
import type { MixerState } from "./types";

type StateSetter<T> = (value: T | ((current: T) => T)) => void;

type MixerStore = {
    mixerState: MixerState | null;
    setMixerState: StateSetter<MixerState | null>;
    selectedItem: string | null;
    setSelectedItem: (value: string | null) => void;
    pending: string | null;
    setPending: (value: string | null) => void;
    commandError: string | null;
    setCommandError: (value: string | null) => void;
    busNameDraft: string | null;
    setBusNameDraft: (value: string | null) => void;
    routeDeviceUID: string;
    setRouteDeviceUID: (value: string) => void;
};

export const useMixerStore = create<MixerStore>((set) => ({
    mixerState: null,
    setMixerState: (value) =>
        set((state) => ({
            mixerState:
                typeof value === "function" ? value(state.mixerState) : value,
        })),
    selectedItem: null,
    setSelectedItem: (selectedItem) => set({ selectedItem }),
    pending: null,
    setPending: (pending) => set({ pending }),
    commandError: null,
    setCommandError: (commandError) => set({ commandError }),
    busNameDraft: null,
    setBusNameDraft: (busNameDraft) => set({ busNameDraft }),
    routeDeviceUID: "",
    setRouteDeviceUID: (routeDeviceUID) => set({ routeDeviceUID }),
}));
