Four definitions for keys that should match and do not. The comment at the top of the section in the file gives the order to try things in: clean the key in an ordinary join first; use these for small tables; use a database for edit distance or volume.

## _bigrams/0, _dice/2
<!-- code: 62c9b2f6 -->

`_bigrams`: the distinct two-character slices of a string, sorted. `explode` turns the string into code points, so slicing is by character and not by byte; `$c[.:. + 2] | implode` is the slice starting at each position; `unique` sorts and removes repeats. A string of one character has none. Anything that is not a string is an error.

`_dice($x; $y)`: twice the number of bigrams the two lists share, divided by the sizes of both. `$x - ($x - $y)` is what the two have in common: jq's array subtraction removes from `$x` everything not in `$y`, and subtracting that from `$x` leaves the rest. If either list is empty the result is 0.

```jq run
("north" | _bigrams), _dice(["ab", "bc", "cd"]; ["bc", "cd", "de", "ef"])
```

Two shared out of three and four: 2 × 2 / 7.

## similarity/2
<!-- code: 54dfbc20 -->

- Null on either side: null.
- A value that is not a string: `_bigrams` is called on it only to raise its error.
- Equal strings: 1, without computing anything. This also covers strings too short to have a bigram, which `_dice` would score 0.
- Otherwise the Dice coefficient of the two bigram lists.

It compares exactly what it is given. Lowercasing and trimming belong in the expressions passed to it.

```jq run
[["Pharmcy", "pharmacy"], ["pharmcy", "pharmacy"], ["a", "a"], ["a", "b"], ["web01", null]]
| map(similarity(.[0]; .[1]) | if . == null then null else round_to(3) end)
```

Hand check of the second: `pharmcy` has `ph ha ar rm mc cy` and `pharmacy` has `ph ha ar rm ma ac cy`; five shared, 2 × 5 / 13 = 0.769. The first pair differs in the capital P as well, which costs the bigram `ph`: 2 × 4 / 13 = 0.615.

## join_fuzzy/7
<!-- code: 749f1e9e -->

Left outer: each left row gets, in field `$as`, the most similar right row of its block.

- **The index**, built once: right rows with a non-null block and string, each stored as `{b: block as text, s: its string, g: its bigrams, r: the row}`, grouped by block. Computing `g` here means each right row's bigrams are computed once, however many left rows it is compared with.
- **Per left row**: a null block or string gives null. Otherwise its bigrams `$g` are computed once, and a `reduce` over the right rows of its block keeps the best candidate: the similarity is 1 for an equal string, else `_dice($g; $c.g)`; a candidate replaces the current best only when its similarity is at least `$min` and strictly greater than the best so far, so on a tie the first in input order stays.
- `$l + {($as): $m}` adds the result, `{similarity, row}` or null.

The cost is one comparison for every pair of a left row and a right row in the same block.

```jq run
[{name: "Radiology North", site: "N"}, {name: "Pharmcy", site: "N"}, {name: "Billing", site: "S"}, {name: "Surgery", site: "S"}, {name: "Lab", site: null}]
| join_fuzzy([{dept: "radiology-north", site: "N"}, {dept: "pharmacy", site: "N"}, {dept: "Biling Office", site: "S"}];
             .site; .site; (.name | ascii_downcase); (.dept | ascii_downcase); 0.5; "match")
| map({name, matched: (.match.row.dept // null), similarity: (.match.similarity | if . == null then null else round_to(3) end)})
```

`Surgery` has nothing in block S at or above 0.5. `Lab` has no block, so it is compared with nothing.
