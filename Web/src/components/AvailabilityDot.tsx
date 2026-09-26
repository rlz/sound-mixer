export function AvailabilityDot({
    status,
}: {
    status: "inactive" | "active" | "problem";
}) {
    const label =
        status === "active"
            ? "Active"
            : status === "problem"
              ? "Problem"
              : "Inactive";

    return (
        <span
            role="img"
            aria-label={label}
            title={label}
            className={`inline-block h-2 w-2 shrink-0 rounded-full ${status === "active" ? "bg-emerald-400" : status === "problem" ? "bg-amber-400" : "bg-slate-500"}`}
        />
    );
}
