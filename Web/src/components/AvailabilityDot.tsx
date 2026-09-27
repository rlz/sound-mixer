export function AvailabilityDot({
    status,
    label,
}: {
    status: "inactive" | "active" | "problem";
    label?: string;
}) {
    const statusLabel =
        label ??
        (status === "active"
            ? "Active"
            : status === "problem"
              ? "Problem"
              : "Inactive");

    return (
        <span
            role="img"
            aria-label={statusLabel}
            title={statusLabel}
            className={`inline-block h-2 w-2 shrink-0 rounded-full ${status === "active" ? "bg-emerald-400" : status === "problem" ? "bg-amber-400" : "bg-slate-500"}`}
        />
    );
}
