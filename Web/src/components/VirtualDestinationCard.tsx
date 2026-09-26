import { faTrashCan } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { ItemCard } from "./ItemCard";
import { LevelControl } from "./LevelControl";

type VirtualDestinationCardProps = {
    name: string;
    kind: "bus" | "BlackHole route";
    available?: boolean;
    selected: boolean;
    gain: number;
    level: number | null;
    captureState?: string;
    onSelect: () => void;
    onGainChange: (gain: number) => Promise<boolean>;
    muted: boolean;
    onMuteChange: (muted: boolean) => Promise<boolean>;
    muteAvailable?: boolean;
    channelCount?: number;
    onDelete: () => void;
    deleteDisabled?: boolean;
};

export function VirtualDestinationCard({
    name,
    kind,
    available,
    selected,
    gain,
    level,
    captureState,
    onSelect,
    onGainChange,
    muted,
    onMuteChange,
    muteAvailable = true,
    channelCount,
    onDelete,
    deleteDisabled = false,
}: VirtualDestinationCardProps) {
    return (
        <ItemCard
            name={name}
            type={kind === "bus" ? "Virtual" : "BlackHole"}
            level={level}
            levelLabel={`${name} ${kind === "bus" ? "virtual bus output" : "BlackHole pair output"}`}
            available={available}
            selected={selected}
            channelCount={channelCount}
            selectOnSurface
            onSelect={onSelect}
            trailingAction={
                <button
                    type="button"
                    disabled={deleteDisabled}
                    aria-label={`Delete ${name}`}
                    title="Delete"
                    className="flex h-7 w-7 shrink-0 items-center justify-center rounded text-rose-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-rose-300 disabled:opacity-50"
                    onClick={onDelete}
                >
                    <FontAwesomeIcon icon={faTrashCan} aria-hidden="true" />
                </button>
            }
        >
            {captureState?.startsWith("unavailable:") && (
                <p className="mt-1 text-xs text-amber-300" role="status">
                    {captureState.slice("unavailable:".length).trim()}
                </p>
            )}
            {captureState === "permissionDenied" && (
                <p className="mt-1 text-xs text-amber-300" role="status">
                    Input capture permission denied.
                </p>
            )}
            <LevelControl
                name={name}
                value={gain}
                muted={muted}
                onMuteChange={(value) => void onMuteChange(value)}
                onLevelChange={onGainChange}
                levelLabel={`${name} ${kind} mix gain`}
                muteDisabled={!muteAvailable}
                muteLabel={
                    !muteAvailable
                        ? "This BlackHole device has no writable mute control"
                        : kind === "BlackHole route"
                          ? "Mutes this BlackHole route wherever it is used"
                          : "Stops this bus from feeding downstream mixes"
                }
            />
        </ItemCard>
    );
}
