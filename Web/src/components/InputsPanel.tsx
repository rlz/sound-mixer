import { memo } from "react";
import { useMixerStore } from "../store";
import { ApplicationInputSource } from "./ApplicationInputSource";
import { PhysicalInputSource } from "./PhysicalInputSource";
import { VirtualInputSource } from "./VirtualInputSource";
import { compareByName } from "../sortByName";

export const InputsPanel = memo(function InputsPanel() {
    const mixerState = useMixerStore((state) => state.mixerState);
    const sourceDevices = (mixerState?.devices ?? [])
        .filter(
            (device) =>
                !device.hidden &&
                (device.inputChannels > 0 ||
                    (mixerState?.mixes ?? []).some((mix) =>
                        mix.inputs.some(
                            (input) =>
                                input.kind === "inputDevice" &&
                                input.id === device.uid,
                        ),
                    )),
        )
        .sort((left, right) =>
            compareByName(
                { name: left.name, id: left.uid },
                { name: right.name, id: right.uid },
            ),
        );
    const buses = [...(mixerState?.buses ?? [])].sort(compareByName);
    const applications = (mixerState?.applications ?? [])
        .filter((application) => application.registered)
        .sort(compareByName);
    return (
        <aside
            className="flex min-h-0 min-w-0 flex-col border-l border-slate-700 bg-slate-900"
            aria-label="Audio sources"
        >
            <h2 className="shrink-0 border-b border-slate-700 px-3.5 py-3 text-sm font-semibold">
                Input
            </h2>
            <div className="min-h-0 flex-1 [scrollbar-gutter:stable] space-y-1 overflow-x-hidden overflow-y-auto overscroll-contain p-3.5">
                {sourceDevices.map((device) => (
                    <PhysicalInputSource
                        key={device.uid}
                        deviceUID={device.uid}
                    />
                ))}
                {buses.map((bus) => (
                    <VirtualInputSource key={bus.id} busID={bus.id} />
                ))}
                {applications.map((application) => (
                    <ApplicationInputSource
                        key={application.id}
                        applicationID={application.id}
                    />
                ))}
                {sourceDevices.length === 0 &&
                    buses.length === 0 &&
                    applications.length === 0 && (
                        <p className="px-3 text-sm text-slate-500">
                            No inputs found.
                        </p>
                    )}
            </div>
        </aside>
    );
});
