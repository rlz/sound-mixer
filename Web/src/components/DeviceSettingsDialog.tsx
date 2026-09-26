import { useState } from "react";
import {
    faEye,
    faEyeSlash,
    faPlus,
    faTrashCan,
    faMinus,
} from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { useMixerStore } from "../store";
import { useMixerCommand } from "../useMixerCommand";
import { DialogShell } from "./DialogShell";
import { compareByName } from "../sortByName";

export function DeviceSettingsDialog({ onClose }: { onClose: () => void }) {
    const state = useMixerStore((store) => store.mixerState);
    const pending = useMixerStore((store) => store.pending);
    const setSelectedItem = useMixerStore((store) => store.setSelectedItem);
    const selectedItem = useMixerStore((store) => store.selectedItem);
    const setBusNameDraft = useMixerStore((store) => store.setBusNameDraft);
    const send = useMixerCommand();
    const [search, setSearch] = useState("");
    const devices = state?.devices ?? [];
    const applications = state?.applications ?? [];
    const registeredApplications = applications
        .filter((application) => application.registered)
        .sort(compareByName);
    const query = search.trim().toLocaleLowerCase();
    const availableApplications = applications
        .filter(
            (application) =>
                application.available &&
                !application.registered &&
                `${application.name} ${application.id}`
                    .toLocaleLowerCase()
                    .includes(query),
        )
        .sort(compareByName);
    const createVirtualDevice = async () => {
        await send("bus-create", { command: "createBus" });
    };
    const deleteBus = async (id: string) => {
        const accepted = await send(`bus-delete:${id}`, {
            command: "deleteBus",
            id,
        });
        if (accepted && selectedItem === `bus:${id}`) {
            setSelectedItem(null);
            setBusNameDraft(null);
        }
    };
    const deleteApplication = async (id: string) => {
        await send(`app-remove:${id}`, {
            command: "removeApplicationInput",
            applicationID: id,
        });
    };

    return (
        <DialogShell
            title="Device settings"
            labelledBy="device-settings-title"
            onClose={onClose}
            className="w-full max-w-2xl"
        >
            <section aria-labelledby="system-devices-heading">
                <h3 id="system-devices-heading" className="font-semibold">
                    System devices
                </h3>
                <p className="mt-1 text-xs text-slate-400">
                    New devices are shown automatically. Hide devices you do not
                    want in the mixer.
                </p>
                <ul className="mt-2 divide-y divide-slate-800">
                    {[...devices]
                        .filter(
                            (device) =>
                                device.hidden ||
                                (device.discovered &&
                                    (device.inputChannels > 0 ||
                                        device.outputChannels > 0)),
                        )
                        .sort((left, right) =>
                            compareByName(
                                { name: left.name, id: left.uid },
                                { name: right.name, id: right.uid },
                            ),
                        )
                        .map((device) => (
                            <li
                                key={device.uid}
                                className="flex items-center justify-between gap-3 py-2"
                            >
                                <span className="min-w-0">
                                    <span className="block truncate">
                                        {device.discovered
                                            ? device.name
                                            : `${device.name} · Disconnected`}
                                    </span>
                                    <span className="block truncate text-xs text-slate-500">
                                        {[
                                            device.inputChannels > 0 && "Input",
                                            device.outputChannels > 0 &&
                                                "Output",
                                        ]
                                            .filter(Boolean)
                                            .join(" · ")}
                                    </span>
                                </span>
                                <button
                                    type="button"
                                    disabled={pending !== null}
                                    aria-label={`${device.hidden ? "Show" : "Hide"} ${device.name}`}
                                    title={
                                        device.hidden
                                            ? "Show device"
                                            : "Hide device"
                                    }
                                    className={`flex size-8 shrink-0 items-center justify-center rounded hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:opacity-50 ${device.hidden ? "text-slate-500" : "text-emerald-300"}`}
                                    onClick={() =>
                                        void send(
                                            `device-visibility:${device.uid}`,
                                            {
                                                command: "setDeviceHidden",
                                                uid: device.uid,
                                                hidden: !device.hidden,
                                            },
                                        )
                                    }
                                >
                                    <FontAwesomeIcon
                                        icon={
                                            device.hidden ? faEyeSlash : faEye
                                        }
                                        aria-hidden="true"
                                    />
                                </button>
                            </li>
                        ))}
                    {devices.every(
                        (device) =>
                            !device.hidden &&
                            (!device.discovered ||
                                (device.inputChannels === 0 &&
                                    device.outputChannels === 0)),
                    ) && (
                        <li className="py-3 text-sm text-slate-500">
                            No system devices found.
                        </li>
                    )}
                </ul>
            </section>

            <section className="mt-5 border-t border-slate-700 pt-4">
                <div className="flex items-center justify-between gap-3">
                    <h3 className="font-semibold">Virtual devices</h3>
                    <button
                        type="button"
                        disabled={pending !== null}
                        className="rounded bg-sky-300 px-3 py-1.5 text-sm font-semibold text-slate-950 disabled:opacity-50"
                        onClick={() => void createVirtualDevice()}
                    >
                        Add virtual device
                    </button>
                </div>
                <ul className="mt-2 space-y-1 text-sm text-slate-300">
                    {[...(state?.buses ?? [])]
                        .sort(compareByName)
                        .map((bus) => (
                            <li
                                key={bus.id}
                                className="flex items-center justify-between gap-3 rounded bg-slate-800/60 px-3 py-2"
                            >
                                <span className="min-w-0 truncate">
                                    {bus.name}
                                </span>
                                <div className="flex shrink-0 items-center gap-1">
                                    <button
                                        type="button"
                                        disabled={
                                            pending !== null ||
                                            bus.channelCount <= 1
                                        }
                                        aria-label={`Remove a channel from ${bus.name}`}
                                        title="Remove channel"
                                        className="flex size-7 items-center justify-center rounded hover:bg-slate-700 disabled:opacity-40"
                                        onClick={() =>
                                            void send(
                                                `bus-channels:${bus.id}`,
                                                {
                                                    command:
                                                        "setBusChannelCount",
                                                    id: bus.id,
                                                    channelCount:
                                                        bus.channelCount - 1,
                                                },
                                            )
                                        }
                                    >
                                        <FontAwesomeIcon
                                            icon={faMinus}
                                            aria-hidden="true"
                                        />
                                    </button>
                                    <label
                                        className="sr-only"
                                        htmlFor={`bus-channel-count-${bus.id}`}
                                    >
                                        Channels for {bus.name}
                                    </label>
                                    <select
                                        id={`bus-channel-count-${bus.id}`}
                                        value={bus.channelCount}
                                        disabled={pending !== null}
                                        aria-label={`Channel count for ${bus.name}`}
                                        className="rounded border border-slate-600 bg-slate-950 px-2 py-1 text-xs"
                                        onChange={(event) =>
                                            void send(
                                                `bus-channels:${bus.id}`,
                                                {
                                                    command:
                                                        "setBusChannelCount",
                                                    id: bus.id,
                                                    channelCount: Number(
                                                        event.currentTarget
                                                            .value,
                                                    ),
                                                },
                                            )
                                        }
                                    >
                                        {Array.from(
                                            { length: 16 },
                                            (_, index) => index + 1,
                                        ).map((count) => (
                                            <option key={count} value={count}>
                                                {count}
                                            </option>
                                        ))}
                                    </select>
                                    <button
                                        type="button"
                                        disabled={
                                            pending !== null ||
                                            bus.channelCount >= 16
                                        }
                                        aria-label={`Add a channel to ${bus.name}`}
                                        title="Add channel"
                                        className="flex size-7 items-center justify-center rounded hover:bg-slate-700 disabled:opacity-40"
                                        onClick={() =>
                                            void send(
                                                `bus-channels:${bus.id}`,
                                                {
                                                    command:
                                                        "setBusChannelCount",
                                                    id: bus.id,
                                                    channelCount:
                                                        bus.channelCount + 1,
                                                },
                                            )
                                        }
                                    >
                                        <FontAwesomeIcon
                                            icon={faPlus}
                                            aria-hidden="true"
                                        />
                                    </button>
                                </div>
                                <button
                                    type="button"
                                    disabled={pending !== null}
                                    aria-label={`Delete ${bus.name}`}
                                    title="Delete virtual device"
                                    className="flex size-8 shrink-0 items-center justify-center rounded text-rose-300 hover:bg-slate-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-rose-300 disabled:opacity-50"
                                    onClick={() => void deleteBus(bus.id)}
                                >
                                    <FontAwesomeIcon
                                        icon={faTrashCan}
                                        aria-hidden="true"
                                    />
                                </button>
                            </li>
                        ))}
                    {(state?.buses.length ?? 0) === 0 && (
                        <li className="text-xs text-slate-500">
                            No virtual devices yet.
                        </li>
                    )}
                </ul>
            </section>

            <section className="mt-5 border-t border-slate-700 pt-4">
                <h3 className="font-semibold">Applications</h3>
                {registeredApplications.length > 0 && (
                    <ul className="mt-2 divide-y divide-slate-800">
                        {registeredApplications.map((application) => (
                            <li
                                key={application.id}
                                className="flex items-center justify-between gap-3 py-2"
                            >
                                <span className="min-w-0 truncate">
                                    {application.name}
                                </span>
                                <button
                                    type="button"
                                    disabled={pending !== null}
                                    aria-label={`Remove ${application.name}`}
                                    title="Remove application and its mix routes"
                                    className="flex size-8 shrink-0 items-center justify-center rounded text-rose-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-rose-300 disabled:opacity-50"
                                    onClick={() =>
                                        void deleteApplication(application.id)
                                    }
                                >
                                    <FontAwesomeIcon
                                        icon={faTrashCan}
                                        aria-hidden="true"
                                    />
                                </button>
                            </li>
                        ))}
                    </ul>
                )}
                <label className="mt-2 block text-xs text-slate-300">
                    Search running applications
                    <input
                        type="search"
                        value={search}
                        onChange={(event) =>
                            setSearch(event.currentTarget.value)
                        }
                        placeholder="Name or bundle identifier"
                        className="mt-1 w-full rounded-lg border border-slate-600 bg-slate-950 px-3 py-2 text-sm text-slate-100 placeholder:text-slate-500"
                    />
                </label>
                <ul className="mt-2 divide-y divide-slate-800">
                    {availableApplications.map((application) => (
                        <li
                            key={application.id}
                            className="flex items-center justify-between gap-3 py-2"
                        >
                            <span className="min-w-0 truncate">
                                {application.name}
                            </span>
                            <button
                                type="button"
                                disabled={pending !== null}
                                aria-label={`Add ${application.name}`}
                                title="Add application"
                                className="flex size-8 shrink-0 items-center justify-center rounded text-sky-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300 disabled:opacity-50"
                                onClick={() =>
                                    void send(
                                        `app-register:${application.id}`,
                                        {
                                            command: "addApplicationInput",
                                            applicationID: application.id,
                                        },
                                    )
                                }
                            >
                                <FontAwesomeIcon
                                    icon={faPlus}
                                    aria-hidden="true"
                                />
                            </button>
                        </li>
                    ))}
                    {availableApplications.length === 0 && (
                        <li className="py-3 text-sm text-slate-500">
                            No eligible running applications are available.
                        </li>
                    )}
                </ul>
            </section>
        </DialogShell>
    );
}
