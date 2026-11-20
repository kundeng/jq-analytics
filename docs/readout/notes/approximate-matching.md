### What it is for

Four definitions for keys that should match and do not: a host typed `WEB01` where the inventory says `web01`, `veb02` for `web02`. The order to try things in: first clean the key inside an ordinary join, for example `join_inner($r; (.name | ascii_downcase); ...)`, because most keys that should match differ only by case, spacing or punctuation. Use the functions here for small tables where that is not enough. For edit distance, or for millions of comparisons, use a database.

```jq run
[{host: "WEB01", site: "N"}, {host: "veb02", site: "N"}, {host: "db1", site: "S"}]
| join_fuzzy([{name: "web01", site: "N"}, {name: "web02", site: "N"}, {name: "db01", site: "S"}];
             .site; .site; (.host | ascii_downcase); .name; 0.6; "match")
| map({host, matched: .match.row.name, similarity: .match.similarity})
```

`WEB01`, lowercased, equals `web01`. `veb02` is closest to `web02`. `db1` scores 0.4 against `db01`, below the minimum of 0.6, so it is left unmatched rather than matched badly.

The measure used is built on bigrams: the two-character pieces of a string. Two strings are alike when they share most of their bigrams. `similarity(a; b)` is the Dice coefficient over the distinct bigrams: twice the number shared, divided by the number in both together, from 0 to 1. `join_fuzzy` is a left outer join on "most similar string", comparing only rows that share an exact key, the block.

### The rules it keeps

- **No cleaning.** The functions compare exactly what they are given; lowercase and trim in the arguments (`.host | ascii_downcase`) if that is wanted. A capital letter costs a bigram: `Web01` and `web01` score 0.75.
- **Equal strings score 1**, even a single character, which has no bigrams; two different strings with no bigrams in common score 0. A null on either side gives null.
- **A block is required.** Rows are compared only within the same exact block key, and a left row with no block or no string gets null. The cost is one comparison per pair of rows in the same block.
- **A match must reach the minimum**; below it the left row's field is null. Among equally similar right rows, the first in input order is kept.
- **Every left row comes back once**, with the field named in `$as` holding `{similarity, row}` or null; order is the left table's.
- **Refuses** a value that is neither a string nor null, and an input or right table that is not a table (page 00).

### Beside core jq, SQL and pandas

Core jq has the cleaning step and nothing else: `ascii_downcase | gsub("[^a-z0-9]"; "")` turns `WEB01` and `web-01 ` both into `web01` on jq 1.7.1, gojq and jaq, and used as a join key it costs nothing (page 30 runs it). There is no similarity function.

SQL engines carry string similarity: DuckDB has `levenshtein` (1 for `db1` and `db01`), `jaro_winkler_similarity` (0.867 for `veb02` and `web02`) and others, and a fuzzy join is a join on the block with a similarity condition:

```sql
SELECT l.id, r.id, jaro_winkler_similarity(l.name, r.name) AS s
FROM l JOIN r ON l.site = r.site
WHERE levenshtein(l.name, r.name) <= 2;
```

pandas has no fuzzy join. Python's standard `difflib.get_close_matches` is the nearest tool at hand: it picks `web02` for `veb02`, and, with its default cutoff of 0.6 on a different ratio, also matches `db1` to `db01`, which the bigram score leaves out. The two measures disagree on short strings; neither is the right one in general, which is why the minimum is the caller's.

What the family adds: a bounded fuzzy join for the case of small tables with no other engine at hand.

### Decisions

- **2026-11-15.** Fuzzy matching left out of the first design.
- **2026-11-18, spec 40, version 0.8.0.** Measured first, on 20,000 pairs of made-up names about 16 characters long: edit distance in jq took 6.3 to 10.4 s on the command-line engines and 22.1 s in the Python jq package, against 0.008 s in DuckDB, with the same answers; roughly a thousand times slower. Edit distance therefore does not ship: at a thousand pairs a second, comparing even 300 rows against 300 takes a minute and a half. A bigram similarity, about 11,000 pairs a second, and a blocked join ship instead; the join refuses to run without a blocking key, so its cost is bounded by the size of the blocks. Cleaning keys stays the first answer. Jaro-Winkler, phonetic codes, token similarity, matching without a block, one-to-many matches and deduplication of a table against itself (pair the matches and use `components`) were left out.

## _bigrams/0, _dice/2
<!-- code: 62c9b2f6 -->

The two helpers under `similarity`. `_bigrams` gives the distinct two-character slices of a string, sorted. `_dice($x; $y)` scores two such lists from 0 to 1 with the Dice coefficient: twice the number of bigrams they share, divided by the sizes of both lists added together.

### The example

The bigrams of two host names, then their score:

```jq run
("web01" | _bigrams), ("web02" | _bigrams), _dice("web01" | _bigrams; "web02" | _bigrams)
```

Each name has four bigrams. They share three (`b0`, `eb`, `we`), so the score is 2 × 3 / (4 + 4) = 0.75.

Edge cases: a string of one character has no bigrams, a list with no bigrams scores 0 against anything, and a value that is not a string is refused.

```jq run
("a" | _bigrams), _dice([]; ["ab"]), (try (5 | _bigrams) catch .)
```

### What happens inside, on the example

`_bigrams`, step 1: `explode` turns the string into a list of code points, one number per character, so slicing is by character and not by byte.

```jq run
"web01" | explode
```

Step 2: for each position but the last, the slice of two code points starting there, turned back into text with `implode`. Step 3: `unique` sorts the slices and removes repeats. The run shows step 2, before `unique`:

```jq run
"web01" | explode as $c | [range(0; ($c | length) - 1) | $c[.:. + 2] | implode]
```

`_dice`: the shared bigrams are found with array subtraction. `$x - $y` is what `$x` has and `$y` lacks; subtracting that from `$x` leaves what both have. The run prints the two subtractions.

```jq run
["01", "b0", "eb", "we"] as $x | ["02", "b0", "eb", "we"] as $y | ($x - $y), ($x - ($x - $y))
```

### The definition

<!-- definition -->

- `_bigrams`: the error message says `similarity` because that is the public function a caller used.
- `_dice`: `if ($x | length) == 0 or ($y | length) == 0 then 0` avoids a division by 0 and scores a string with no bigrams as unlike everything.
- `2 * (shared | length) / (($x | length) + ($y | length))` is the coefficient.

## similarity/2
<!-- code: 54dfbc20 -->

How alike two strings are, from 0 to 1. Databases offer the same idea as trigram similarity; this one uses bigrams.

### The example

Six pairs:

```jq run
[["web01", "web02"], ["Web01", "web01"], ["db01", "db1"], ["a", "a"], ["a", "b"], ["web01", null]]
| map(similarity(.[0]; .[1]))
```

- `web01` and `web02`: 0.75, as worked out above.
- `Web01` and `web01`: also 0.75. The capital W costs the bigram `We`. The function compares exactly what it is given; lowercase and trim in the arguments if that is wanted.
- `db01` and `db1`: `db01` has `db`, `b0`, `01` and `db1` has `db`, `b1`. One shared: 2 × 1 / (3 + 2) = 0.4.
- `a` and `a`: equal strings give 1, even though a one-character string has no bigrams.
- `a` and `b`: 0.
- A null on either side gives null.

A value that is neither a string nor null is an error:

```jq run
try similarity("a"; 5) catch .
```

### Reading the call

Both arguments are filters, run on the input of `similarity`. In `map(similarity(.[0]; .[1]))` the input is one pair, and the two filters pick its two members. On a table row it would read `similarity(.name; .alias)`.

### The definition

<!-- definition -->

- `(a) as $a | (b) as $b` runs both filters once and names the results.
- `if $a == null or $b == null then null`.
- The two `elif ... != "string"` branches call `_bigrams` on the bad value to raise its error.
- `elif $a == $b then 1` answers equal strings without computing anything, and covers strings too short to have a bigram, which `_dice` would score 0.
- `else _dice($a | _bigrams; $b | _bigrams)`.

## join_fuzzy/7
<!-- code: 03bd6684 -->

A left outer join on "most similar string": each left row gets the right row whose string is most like its own, if the similarity reaches a minimum. Rows are compared only when they share an exact key, the block, which keeps the number of comparisons down.

### The example

Host names typed by hand, to be matched to an inventory. Left rows:

| host | site |
|---|---|
| WEB01 | N |
| veb02 | N |
| db1 | S |
| lab01 | null |

Inventory (the right table):

| name | site |
|---|---|
| web01 | N |
| web02 | N |
| db01 | S |

The block is the site, the left string is the host in lower case, and the minimum similarity is 0.6.

```jq run
[{host: "WEB01", site: "N"}, {host: "veb02", site: "N"}, {host: "db1", site: "S"}, {host: "lab01", site: null}]
| join_fuzzy([{name: "web01", site: "N"}, {name: "web02", site: "N"}, {name: "db01", site: "S"}];
             .site; .site; (.host | ascii_downcase); .name; 0.6; "match")
```

Every left row comes back with a `match` field. `WEB01` in lower case equals `web01`: similarity 1. `veb02` is closest to `web02` at 0.75. `db1` scores 0.4 against `db01`, below the minimum, so its match is null. `lab01` has no site, so it is compared with nothing.

### Reading the call

| Argument | In the example | Runs on | Meaning |
|---|---|---|---|
| `$right` | the inventory | nothing: a value | the table to match against |
| `lblock` | `.site` | one left row | the exact key the row must share with a right row |
| `rblock` | `.site` | one right row | the same, on the right |
| `lstr` | `.host` then `ascii_downcase` | one left row | the string to compare |
| `rstr` | `.name` | one right row | the string to compare it with |
| `$min` | `0.6` | nothing: a value | the lowest similarity that counts as a match |
| `$as` | `"match"` | nothing: a value | the name of the field added to each left row |

### What happens inside, on the example

Step 1, the index `$ix`, built once: the right rows grouped by block. Each is stored with its block as JSON text (`b`), its string (`s`), its bigrams (`g`) and the row itself (`r`).

```jq run
[{name: "web01", site: "N"}, {name: "web02", site: "N"}, {name: "db01", site: "S"}]
| [.[] | select((.site) != null and (.name) != null) | {b: (.site | tojson), s: (.name), g: (.name | _bigrams), r: .}]
| group_by(.b) | map({key: .[0].b, value: .}) | from_entries
```

Step 2, per left row: its bigrams are computed once and scored against each candidate of its block, in input order. For `veb02` in block N, the run prints its bigrams, then its score against `web01` and against `web02`.

```jq run
("veb02" | _bigrams) as $g | $g, _dice($g; "web01" | _bigrams), _dice($g; "web02" | _bigrams)
```

Step 3: the best candidate is kept. `web01` scores 0.5, below the minimum of 0.6, so nothing is kept yet. `web02` scores 0.75, which reaches the minimum, and becomes the match.

Step 4: the left row gets the field: `{similarity: 0.75, row: the web02 row}`, or null when nothing was kept.

### The definition

<!-- definition -->

- `select((rblock) != null and (rstr) != null)`: a right row with no block or no string is left out of the index. Storing `g` in the index means each right row's bigrams are computed once, however many left rows it is compared with.
- `if $bk == null or $s == null then null`: a left row with no block or no string gets null.
- `reduce ($ix[$bk | tojson] // [])[] as $c (null; ...)` walks the block's candidates; a block the right table lacks has none.
- `if $c.s == $s then 1 else _dice($g; $c.g) end` is the same rule as `similarity`: equal strings score 1.
- `if $sim >= $min and (. == null or $sim > .similarity)`: a candidate replaces the best so far only when it is strictly better, so among equally similar right rows the first in input order stays.
- `$l + {($as): $m}` adds the result under the name in `$as`.
- The cost is one comparison for every pair of a left row and a right row in the same block, so choose blocks that stay small.
