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
built-in food database. If backup is set up, a verified safety copy of
everything goes into Previous backups first, and the erase only happens
once that copy is proven readable; restoring it brings everything back. If
the copy fails, nothing is erased. Without backup there is no copy, and the
confirmation says so.

The bundled USDA spine is never in a backup — it ships with every install.
