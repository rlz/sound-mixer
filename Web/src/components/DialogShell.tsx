import { useEffect, useRef, type ReactNode } from "react";

type Props = {
    title: string;
    labelledBy: string;
    onClose: () => void;
    children: ReactNode;
    className?: string;
    bodyClassName?: string;
    onDialogKeyDown?: (event: React.KeyboardEvent<HTMLElement>) => void;
};

export function DialogShell({
    title,
    labelledBy,
    onClose,
    children,
    className = "w-full max-w-lg",
    bodyClassName = "",
    onDialogKeyDown,
}: Props) {
    const closeRef = useRef<HTMLButtonElement>(null);

    useEffect(() => {
        const trigger = document.activeElement as HTMLElement | null;
        closeRef.current?.focus();
        return () => trigger?.focus();
    }, []);

    return (
        <div
            className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4"
            onMouseDown={(event) => {
                if (event.target === event.currentTarget) onClose();
            }}
        >
            <section
                role="dialog"
                aria-modal="true"
                aria-labelledby={labelledBy}
                onKeyDown={(event) => {
                    if (event.key === "Escape") onClose();
                    onDialogKeyDown?.(event);
                }}
                className={`flex max-h-[90vh] flex-col overflow-hidden rounded-xl border border-slate-700 bg-slate-900 text-sm text-slate-100 shadow-2xl ${className}`}
            >
                <header className="flex shrink-0 items-center justify-between gap-3 border-b border-slate-700 px-4 py-3">
                    <h2 id={labelledBy} className="text-base font-semibold">
                        {title}
                    </h2>
                    <button
                        ref={closeRef}
                        type="button"
                        aria-label="Close dialog"
                        title="Close"
                        className="flex size-8 shrink-0 items-center justify-center rounded text-lg leading-none text-slate-300 hover:bg-slate-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-300"
                        onClick={onClose}
                    >
                        ×
                    </button>
                </header>
                <div className={`min-h-0 overflow-y-auto p-4 ${bodyClassName}`}>
                    {children}
                </div>
            </section>
        </div>
    );
}
