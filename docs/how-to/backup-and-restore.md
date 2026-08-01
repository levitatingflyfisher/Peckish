# Back up and restore

Settings → **Your data**.

**Encrypted backup (.ohbk)** — the sanctuary section walks you through a
household seed phrase once, then writes an encrypted `.ohbk` file you can
keep anywhere (drive, email to yourself, another phone). Restore picks a
file, previews what's inside (age, source app), states exactly what it will
replace, and only then writes. Restores are atomic: a failure partway leaves
current data untouched.

**Plain export** — a readable JSON copy of everything (diary, foods, meals,
recipes, plan, groceries, targets, regulars). The file is the interface:
keep it, grep it, move it.

**Erase all data** — deletes the user tables, keeps your theme and the
built-in food database. The confirmation lists what goes; the list is
test-bound to the truth.

The bundled USDA spine is never in a backup — it ships with every install.
