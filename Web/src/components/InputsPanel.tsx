import { memo } from "react";
import { useMixerStore } from "../store";
import { ItemGroup } from "./ItemGroup";
import { ApplicationInputsGroup } from "./ApplicationInputsGroup";
import { PhysicalInputSources } from "./PhysicalInputSources";
import { VirtualInputSources } from "./VirtualInputSources";

export const InputsPanel = memo(function InputsPanel() {
    const mixerState = useMixerStore((state) => state.mixerState);
    const sourceDevices = (mixerState?.devices ?? []).filter(
        (device) =>
            device.inputChannels > 0 ||
            (mixerState?.mixes ?? []).some((mix) =>
                mix.inputs.some(
                    (input) =>
                        input.kind === "inputDevice" && input.id === device.uid,
                ),
            ),
    );
    return (
        <>
            <aside
                className="min-h-0 min-w-0 [scrollbar-gutter:stable] space-y-3.5 overflow-x-hidden overflow-y-auto overscroll-contain border-l border-slate-700 bg-slate-900 p-3.5"
                aria-label="Audio sources"
            >
                <ItemGroup title="System">
                    {sourceDevices.length === 0 &&
                        (mixerState?.buses.length ?? 0) === 0 && (
                            <p className="px-3 text-sm text-slate-500">
                                No inputs found.
                            </p>
                        )}
                    <PhysicalInputSources />
                    <VirtualInputSources />
                </ItemGroup>
                <ApplicationInputsGroup />
            </aside>
        </>
    );
});
