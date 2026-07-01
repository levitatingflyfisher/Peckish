# Design philosophy

**The two-tap law.** A regular meal logs in one tap (the recents rail);
anything else in two (the + sheet). If a flow grows a third obligatory tap,
the flow is wrong. This came from watching a sibling app (Furrow) invert its
own loop — the grid that should have been *output* became the input surface.

**Nutrition describes meals.** The week's dinners are a household fact. The
app states facts in a calm voice and never editorializes: no streaks, no
red, no push. See ADR-0003.

**Unknown is never zero.** A custom food with no protein entered reports
protein as unknown; a day of kcal-only entries has unknown protein, not 0 g.
Faking zeros would quietly poison every total downstream.

**The ledger never rewrites.** Diary entries snapshot their macros at log
time. Editing a food or deleting a recipe changes the future, never the
past.

**The grocery list is a projection with three laws.** Manual adds always
survive regeneration; checked items survive and suppress duplicates;
unchecked generated lines follow the plan wholesale. The aisle classifier is
deliberately dumb — a roughly-sorted list beats an unsorted one, and the
user out-ranks the classifier by simply not caring.

**CRUD completeness is table stakes.** Everything visible can be edited,
deleted, archived, or reset. Forgiveness over prevention applies to data.
