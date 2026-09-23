import React from "react";

export function ItemGroup({
    title,
    children,
}: {
    title: string;
    children: React.ReactNode;
}) {
    return (
        <section
            aria-label={title}
            className="rounded-xl border border-slate-800 bg-slate-900 p-3"
        >
            <h2 className="mb-2 px-3 text-xs font-semibold uppercase tracking-wider text-slate-400">
                {title}
            </h2>
            <div className="space-y-1">{children}</div>
        </section>
    );
}
