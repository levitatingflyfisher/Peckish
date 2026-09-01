# Personas

Agents drive the real Peckish build as these people, per the fleet testing
rule. Each scenario gives a start state, plain steps, what success looks like,
and what to check. "Standard checks" means: text scale 1.3 at 360 dp width,
dark mode (with the phone's system theme set to dark), airplane mode, and
every error in plain words with a way forward. Scenarios aim at the weak
spots found by the September 2026 lens audit.

## Primary: Kofi, who plans dinners for a household of five

Kofi is 44 and plans the week's dinners for their partner, two school-age
kids, and their partner's mother, who lives with them. Sunday afternoon is
planning time at the kitchen table; weekday evenings are cooking.

- **Goal:** save recipes, plan seven dinners, and turn the week into a
  grocery list without retyping anything.
- **Context:** two hands on Sunday, one greasy hand on weeknights, the shop
  one-handed with a trolley, no signal inside the store.
- **Would quit if:** a long recipe is lost, or an import fails with gibberish.

**K1. First run.** Start: fresh install. Steps: read the Today screen; follow
its instruction. Success: the empty state does not say "Tap a regular above"
when no regulars exist; it points at something real. Check: standard checks;
instruction text is readable, not faint grey.

**K2. Import a recipe offline.** Start: Recipes tab, airplane mode on. Steps:
add a recipe from a link; paste any recipe URL; confirm. Success: a busy state
shows while it tries; failure appears in plain words with Retry, not
"ClientException: Failed to fetch". Check: the dialog does not vanish before
the result.

**K3. Write a long recipe and slip.** Start: Recipes tab. Steps: create a
recipe, type ten ingredient lines without a title, tap Save; then use the
system back gesture. Success: Save explains the missing title or supplies one;
back does not discard the typing. Check: text scale 1.3.

**K4. Week to list.** Start: three recipes saved. Steps: plan them on Mon,
Wed, Fri; go to Groceries while it is empty. Success: Groceries offers to
build the list from this week's plan; on Plan the control is reachable
without scrolling. Check: Plan's app bar names the page.

**K5. Swipe and clear in the aisle.** Start: a 15-line generated list, 5
ticked. Steps: swipe one unticked line away by mistake; then clear checked
items. Success: both offer Undo with a count; "Clear checked" is a word, not
a lone glyph. Check: undo after delete; offline.

## Secondary: Hyun, keeping their own carb numbers

Hyun is 61, Kofi's partner's mother, manages type 2 diabetes, and uses the
optional diary with large text. The rest of the household never sees it.

- **Goal:** log the planned dinner and see the month's carbs.
- **Context:** text scale 1.3, reading glasses, evenings after dinner.
- **Would quit if:** logging the family dinner means searching for it.

**H1. Log what was planned.** Start: tonight's plate holds a recipe with
nutrition. Steps: try to log tonight's dinner in the diary. Success: there is
a direct way to log the planned dinner, or the gap is recorded as a finding.
Check: plan rows show kcal where known.

**H2. History.** Start: a month of logs. Steps: open History; read carbs.
Success: axis labels grow with text size; a 1,200 kcal day looks about half as
dark as a 2,400 day. Check: dark mode.

**H3. Follow the phone's theme.** Start: phone system theme set to dark.
Steps: open Peckish. Success: the app opens dark without visiting Settings.
Check: contrast of instructional text in both themes.
