# Approximate matching

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/approximate-matching.md`. Do not edit.

Four definitions for keys that should match and do not. The comment at the top of the section in the file gives the order to try things in: clean the key in an ordinary join first; use these for small tables; use a database for edit distance or volume.

## _bigrams, _dice

`_bigrams/0`, lines 1079 to 1081:

```jq
# the distinct two-character slices of a string, sorted
def _bigrams:
  if type != "string" then error("similarity: \(tojson) is not a string")
  else explode as $c | [range(0; ($c | length) - 1) | $c[.:. + 2] | implode] | unique end;
```

`_dice/2`, lines 1082 to 1084:

```jq
def _dice($x; $y):
  if ($x | length) == 0 or ($y | length) == 0 then 0
  else 2 * (($x - ($x - $y)) | length) / (($x | length) + ($y | length)) end;
```

`_bigrams`: the distinct two-character slices of a string, sorted. `explode` turns the string into code points, so slicing is by character and not by byte; `$c[.:. + 2] | implode` is the slice starting at each position; `unique` sorts and removes repeats. A string of one character has none. Anything that is not a string is an error.

`_dice($x; $y)`: twice the number of bigrams the two lists share, divided by the sizes of both. `$x - ($x - $y)` is what the two have in common: jq's array subtraction removes from `$x` everything not in `$y`, and subtracting that from `$x` leaves the rest. If either list is empty the result is 0.

```jq
("north" | _bigrams), _dice(["ab", "bc", "cd"]; ["bc", "cd", "de", "ef"])
```

```json
["no","or","rt","th"]
0.5714285714285714
```

Two shared out of three and four: 2 × 2 / 7.

## similarity

`similarity/2`, lines 1090 to 1095:

```jq
# similarity: how alike two strings are, from 0 to 1: the Dice coefficient over their distinct
# character bigrams (twice the bigrams they share, divided by the bigrams of both). Equal strings
# give 1, including strings too short to have a bigram; null on either side gives null. It compares
# what it is given: lowercase and trim in the expressions if that is wanted.
def similarity(a; b):
  (a) as $a | (b) as $b
  | if $a == null or $b == null then null
    elif ($a | type) != "string" then ($a | _bigrams) elif ($b | type) != "string" then ($b | _bigrams)
    elif $a == $b then 1
    else _dice($a | _bigrams; $b | _bigrams) end;
```

- Null on either side: null.
- A value that is not a string: `_bigrams` is called on it only to raise its error.
- Equal strings: 1, without computing anything. This also covers strings too short to have a bigram, which `_dice` would score 0.
- Otherwise the Dice coefficient of the two bigram lists.

It compares exactly what it is given. Lowercasing and trimming belong in the expressions passed to it.

```jq
[["Pharmcy", "pharmacy"], ["pharmcy", "pharmacy"], ["a", "a"], ["a", "b"], ["web01", null]]
| map(similarity(.[0]; .[1]) | if . == null then null else round_to(3) end)
```

```json
[0.615,0.769,1,0,null]
```

Hand check of the second: `pharmcy` has `ph ha ar rm mc cy` and `pharmacy` has `ph ha ar rm ma ac cy`; five shared, 2 × 5 / 13 = 0.769. The first pair differs in the capital P as well, which costs the bigram `ph`: 2 × 4 / 13 = 0.615.

## join_fuzzy

`join_fuzzy/7`, lines 1103 to 1113:

```jq
# join_fuzzy (left outer): each left row with field $as holding {similarity, row} for the right row
# of the same block whose rstr is most similar to the left row's lstr, when that similarity is at
# least $min; null otherwise. lblock and rblock give an exact key two rows must share to be
# compared at all (a site, a first letter): the cost is one comparison per pair of rows that share
# a block, so choose blocks that stay small. Among equally similar right rows, the first in input
# order. A null block or a null string never matches.
def join_fuzzy($right; lblock; rblock; lstr; rstr; $min; $as):
  ([$right[] | select((rblock) != null and (rstr) != null) | {b: (rblock | tojson), s: (rstr), g: (rstr | _bigrams), r: .}]
   | group_by(.b) | map({key: .[0].b, value: .}) | from_entries) as $ix
  | map(. as $l | ($l | lblock) as $bk | ($l | lstr) as $s
      | (if $bk == null or $s == null then null
         else ($s | _bigrams) as $g
           | reduce ($ix[$bk | tojson] // [])[] as $c (null;
               (if $c.s == $s then 1 else _dice($g; $c.g) end) as $sim
               | if $sim >= $min and (. == null or $sim > .similarity) then {similarity: $sim, row: $c.r} else . end)
         end) as $m
      | $l + {($as): $m});
```

Left outer: each left row gets, in field `$as`, the most similar right row of its block.

- **The index**, built once: right rows with a non-null block and string, each stored as `{b: block as text, s: its string, g: its bigrams, r: the row}`, grouped by block. Computing `g` here means each right row's bigrams are computed once, however many left rows it is compared with.
- **Per left row**: a null block or string gives null. Otherwise its bigrams `$g` are computed once, and a `reduce` over the right rows of its block keeps the best candidate: the similarity is 1 for an equal string, else `_dice($g; $c.g)`; a candidate replaces the current best only when its similarity is at least `$min` and strictly greater than the best so far, so on a tie the first in input order stays.
- `$l + {($as): $m}` adds the result, `{similarity, row}` or null.

The cost is one comparison for every pair of a left row and a right row in the same block.

```jq
[{name: "Radiology North", site: "N"}, {name: "Pharmcy", site: "N"}, {name: "Billing", site: "S"}, {name: "Surgery", site: "S"}, {name: "Lab", site: null}]
| join_fuzzy([{dept: "radiology-north", site: "N"}, {dept: "pharmacy", site: "N"}, {dept: "Biling Office", site: "S"}];
             .site; .site; (.name | ascii_downcase); (.dept | ascii_downcase); 0.5; "match")
| map({name, matched: (.match.row.dept // null), similarity: (.match.similarity | if . == null then null else round_to(3) end)})
```

```json
[
  {"name": "Radiology North", "matched": "radiology-north", "similarity": 0.857},
  {"name": "Pharmcy", "matched": "pharmacy", "similarity": 0.769},
  {"name": "Billing", "matched": "Biling Office", "similarity": 0.556},
  {"name": "Surgery", "matched": null, "similarity": null},
  {"name": "Lab", "matched": null, "similarity": null}
]
```

`Surgery` has nothing in block S at or above 0.5. `Lab` has no block, so it is compared with nothing.
