# Import a recipe from a link

Recipes → **+** → *Paste a recipe link* → paste the URL → **Fetch**.

Peckish fetches that one page, reads its schema.org/Recipe markup (the same
structured data Google reads), and shows you the parsed result — title,
servings, ingredient lines, instructions, and per-serving nutrition if the
site published it. Fix anything, then save. Nothing enters the box unseen.

**When it fails:** some sites don't publish recipe markup, serve it broken,
or block non-browser fetches outright. The honest fallback is right there —
*Write one down* — and pasting the ingredients into the editor takes about a
minute. Import quality across the web is a moving target (sites break their
own markup routinely); Peckish's parser covers the mainstream shapes and
refuses gracefully otherwise.
