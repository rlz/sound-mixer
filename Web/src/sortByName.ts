const nameCollator = new Intl.Collator("en", {
    numeric: true,
    sensitivity: "base",
});

export function compareByName(
    left: { name: string; id: string },
    right: { name: string; id: string },
) {
    return (
        nameCollator.compare(left.name, right.name) ||
        nameCollator.compare(left.id, right.id)
    );
}
