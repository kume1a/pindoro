# Lane families: data check

The pipeline's family step (`apps/pipeline/sql/80_learning.sql`) reads families from the Georgian
names: `<prefix> <Roman numeral> <შესახვევი | ჩიხი | გასასვლელი>` is a child of the nearest street
whose name the prefix starts (its name minus the type word, or its last word in the genitive). A
build prints this check and writes it to `apps/pipeline/out/<city>/family-check.md`.

Tbilisi, Geofabrik extract of 2026-11-08, pack build of 2026-11-16:

| Measure                                                      | Streets | Share  |
| ------------------------------------------------------------ | ------- | ------ |
| Names ending in შესახვევი, ჩიხი or გასასვლელი                | 1715    |        |
| … with a Roman numeral                                       | 1507    | 87.9 % |
| Children with a parent (lane 706, dead end 642, passage 137) | 1485    | 98.5 % |
| … within 500 m of the parent                                 | 1454    | 97.9 % |
| … within 1.5 km of the parent                                | 1465    | 98.7 % |
| Orphans (over 1.5 km)                                        | 20      | 1.3 %  |

Numbered names without a parent (22): აეროდრომის დასახლება III ქუჩის II გასასვლელი, აეროდრომის დასახლება III ქუჩის I გასასვლელი, გიგო ზაზიაშვილი III შესახვევი, გიგო ზაზიაშვილი II შესახვევი, ვაჟა–ფშაველას I შესახვევი, ზემო ვეძისის II ჩიხი, თბილისი-კოჯორის შესახვევის I ჩიხი, ივანეს თუმანიანის IV ჩიხი, კოტე აფხასის I ჩიხი, ლევან მიქელაძის I ჩიხი, მელაანის II შესახვევი, ნეკრესის I შესახვევი, პეტრე ქავთარაძე II შესახვევი, რავაზ თაბუკაშვილის I ჩიხი, ტყეკულტურის IV შესახვევი, ჩახრუხაძის II შესახვევი, ძმობის II ჩიხი, ჯანსულ კორძაიას I ჩიხი, ჰენრიკ პრინევსკის III ჩიხი, ჰენრიკ პრინევსკის IV ჩიხი, ჰენრიკ პრინევსკის I ჩიხი, ჰენრიკ პრინევსკის V ჩიხი.

Orphans (child → parent, km):

- პეტრე მელიქიშვილის I ჩიხი → პეტრე მელიქიშვილის გამზირი, 13.6
- თამარ მეფის II ჩიხი → თამარ მეფის გამზირი, 13.1
- თამარ მეფის III ჩიხი → თამარ მეფის გამზირი, 13.1
- თამარ მეფის IV ჩიხი → თამარ მეფის გამზირი, 13
- თამარ მეფის I ჩიხი → თამარ მეფის გამზირი, 12.9
- საირმის III შესახვევი → საირმის ქუჩა, 9.2
- საირმის II ჩიხი → საირმის ქუჩა, 9.2
- საირმის V ჩიხი → საირმის ქუჩა, 9.1
- საირმის III ჩიხი → საირმის ქუჩა, 9.1
- საირმის IV ჩიხი → საირმის ქუჩა, 9.1
- ყვარლის VI შესახვევი → ყვარლის ქუჩა, 8.5
- ყვარლის II შესახვევი → ყვარლის ქუჩა, 8.5
- ნავთლუღის VII შესახვევი → ნავთლუღის ქუჩა, 6
- დავით აღმაშენებლის VII ჩიხი → დავით აღმაშენებლის გამზირი, 5.5
- დავით აღმაშენებლის VI ჩიხი → დავით აღმაშენებლის ქუჩა, 5.4
- დავით აღმაშენებლის V ჩიხი → დავით აღმაშენებლის ქუჩა, 5.3
- დავით აღმაშენებლის III ჩიხი → დავით აღმაშენებლის ქუჩა, 5.1
- დავით აღმაშენებლის II ჩიხი → დავით აღმაშენებლის ქუჩა, 4.8
- დავით აღმაშენებლის I ჩიხი → დავით აღმაშენებლის ქუჩა, 4.7
- ვახტანგ გორგასალის III ჩიხი → ვახტანგ გორგასალის მოედანი, 2.9

## Reading it

- 98.7 % of the children lie within 1.5 km of their parent, so the family rules (intros, the sibling
  cap, confusables) cover nearly every numbered lane.
- The 208 names without a numeral ("ბესარიონ ჟღენტის ჩიხი") are ordinary streets: SPEC §16.5 needs
  the numeral.
- Most children without a parent misspell it ("გიგო ზაზიაშვილი" for "ზაზიაშვილის") or belong to a
  street missing from OSM. Fixing them is an OSM edit, not a pipeline rule.
- The orphans share a name with a far-off avenue: a suburb's lanes named after a street that isn't
  there. They stay orphans; the curriculum treats them as ordinary streets.
