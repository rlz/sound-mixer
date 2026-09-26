import React from "react";

export function ItemGroup({
    title,
    children,
}: {
    title: string;
    children: React.ReactNode;
}) {
    return (
        <section aria-label={title} className="border-b border-slate-800 pb-4">
            <h2 className="mb-2 px-3 text-xs font-semibold tracking-wider text-slate-400 uppercase">
                {title}
            </h2>
            <div className="space-y-1">{children}</div>
        </section>
    );
}
