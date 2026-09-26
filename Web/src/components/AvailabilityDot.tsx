export function AvailabilityDot({ available }: { available: boolean }) {
    const status = available ? "Available" : "Disconnected";

    return (
        <span
            role="img"
            aria-label={status}
            title={status}
            className={`inline-block h-2 w-2 shrink-0 rounded-full ${available ? "bg-emerald-400" : "bg-amber-400"}`}
        />
    );
}
