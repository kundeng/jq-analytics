# A primer on jq, from the questions people ask

What to know about jq before any function of this library helps. It is built from two surveys of what people ask about jq (`docs/research/questions-2026-11-19.md`): the 200 highest-voted Stack Overflow questions of all time and the questions of the last twelve months. Most of those questions are not about analytics at all. They come from two places: jq's own model of evaluation, and the shell around it. Each section below starts from a question people really ask, shows a small run with its output, and shows the version that goes wrong.

Every example runs as `jq -n '<program>'` and gives the same output on jq 1.7.1, jq 1.8.2, gojq and jaq, unless the section says otherwise.

## 1. One value in, one or many out

*The question:* "Why does `length` print 2 twice?" "Why do I get one line per element?"

A jq program is a filter. It receives one value, and it may give back no value, one value or several. `.[]` gives back every element of an array as a separate value, and whatever comes after the `|` runs once for each.

```jq
[{"host":"web01","ram":16},{"host":"db01","ram":64}] | .[] | .host
```

```json
"web01"
"db01"
```

Two values, not an array. To get an array back, collect the values with `[ ... ]`, or use `map`, which is the same thing written shorter:

```jq
[{"host":"web01","ram":16},{"host":"db01","ram":64}] | map(.host)
```

```json
["web01","db01"]
```

The wrong version: `.[] | length` asks for the length of each row (two fields each), not of the table.

```jq
[{"host":"web01","ram":16},{"host":"db01","ram":64}] | .[] | length
```

```json
2
2
```

`length` on the array itself is the number of rows, 2, printed once.

Several values can flow into a step. Each one goes through it on its own:

```jq
1, 2 | . * 10
```

```json
10
20
```

**This library takes the whole table as one value.** `$rows | group_agg(...)` is right; `$rows[] | group_agg(...)` hands it one row at a time, and since 0.14.0 it stops and says so:

```text
group_agg: the input is one object, not a table (an array of rows). Pass the whole table as one value: $rows | group_agg(...), not $rows[] | group_agg(...).
```

**A file of JSON lines is many values.** Each line is one value, and the program runs once per line. To work on all of them as one table, collect them, with `--slurp` or with `-n` and `[inputs]`:

```bash
printf '{"host":"web01","ram":16}\n{"host":"db01","ram":64}\n' > hosts.jsonl
jq -c 'length' hosts.jsonl              # 2, then 2: the fields of each line
jq -c --slurp 'length' hosts.jsonl      # 2: the lines, as one array
jq -c -n '[inputs] | length' hosts.jsonl   # 2: the same
```

`--slurp` reads the whole file into one array first. `-n` with `inputs` reads the values one by one, which lets a program keep only what it needs (`[inputs | select(.ram > 32)]`).

## 2. Selecting: `select` drops a value, it does not say false

*The question:* "Select objects based on the value of a field" (557 votes, 823,000 views); "filter an array of objects on a value in an inner array" (518 votes).

`select(cond)` gives back its input when the condition is true, and *nothing* when it is false. It is a filter, not a test.

```jq
[{"host":"web01","ram":16},{"host":"db01","ram":64}] | map(select(.ram > 32))
```

```json
[{"host":"db01","ram":64}]
```

The trap is a condition that gives several values. `.tags[] == "p2"` is one comparison per tag, so a row whose tags hold `"p2"` twice is kept twice:

```jq
[{"host":"web01","tags":["p2","p2"]},{"host":"db01","tags":["p1"]}] | map(select(.tags[] == "p2"))
```

```json
[{"host":"web01","tags":["p2","p2"]},{"host":"web01","tags":["p2","p2"]}]
```

`any(generator; condition)` asks the question once:

```jq
[{"host":"web01","tags":["p2","p2"]},{"host":"db01","tags":["p1"]}] | map(select(any(.tags[]; . == "p2")))
```

```json
[{"host":"web01","tags":["p2","p2"]}]
```

The same thing happens in `if`. The condition runs once per value it gives, so `if` can give several answers, or none at all:

```jq
{a: [1, 2]} | if .a[] > 1 then "big" else "small" end
```

```json
"small"
"big"
```

With `{a: []}` the condition gives no value, so the `if` gives nothing: neither branch runs. A question in 2026 reported this as a bug ("if with paths never evaluates the else path", jq #3616). Ask `any(.a[]; . > 1)` instead, which is always one true or false.

`not` is a filter too, applied to its input: `null` and `false` give `true`, everything else (`0` and `""` included) gives `false`.

```jq
[1, null, false, 0, ""] | map(not)
```

```json
[false,true,true,false,false]
```

## 3. Building objects and arrays

*The question:* "Select multiple fields" (317 votes); "get the key names" (314 votes).

`{host, where: .site}` builds a new object: `host` is short for `host: .host`. A key computed from the data goes in parentheses:

```jq
{host: "web01", site: "N"} | {host, where: .site}
```

```json
{"host":"web01","where":"N"}
```

```jq
{key: "web01", value: 16} | {(.key): .value}
```

```json
{"web01":16}
```

The surprise: a field whose value gives several values makes several objects, one for every combination.

```jq
{host: ("web01", "db01"), ram: (16, 64)}
```

```json
{"host":"web01","ram":16}
{"host":"web01","ram":64}
{"host":"db01","ram":16}
{"host":"db01","ram":64}
```

This is how `{name: .users[].name}` turns one object into many. Collect with `[ ... ]` where one value is meant.

## 4. Variables, `reduce`, and what binds first

*The question:* "How do I keep a running total?" "Why does `x = y // z` not do what I meant?"

`expr as $x | rest` names a value for the rest of the program. `reduce` folds many values into one:

```jq
[3, 1, 2] | reduce .[] as $v (0; . + $v)
```

```json
6
```

Most hand-written `reduce` programs in Stack Overflow answers are a GROUP BY, a join or a running total in disguise, and most of them get nulls wrong. That is what this library's `group_agg`, the joins and `window` with `running_sum` are for.

**Precedence.** `|` binds loosest, then `,`, then `//`, then the arithmetic and comparison operators. `=` and `|=` are where engines disagree:

```text
{} | .a = .b // "none"
jq 1.7.1, gojq:  {"a":null}
jaq 3.1.2:       {"a":"none"}
```

Write the parentheses: `.a = (.b // "none")` gives `{"a":"none"}` everywhere. A 2026 report asks about exactly this ("Strange `x = y // z` precedence", jq #3507).

## 5. What the error messages mean

*The question:* "Cannot index string with string" (115 votes, 201,000 views, and still asked in 2026).

| Message (jq 1.7.1) | What happened | Usually |
|---|---|---|
| `Cannot index string with string "host"` | `.host` was applied to a string | the value is one level further down than you think, or it is JSON inside a string (section 6) |
| `Cannot index array with string "host"` | `.host` on an array | you meant `.[].host` or `map(.host)` |
| `Cannot index object with number` | `.[0]` on an object | the value is an object, not an array |
| `Cannot iterate over null` | `.[]` on null | the field is missing; `.items[]?` or `(.items // [])[]` |

The engines word these differently: gojq says `expected an object but got: string ("web01")`, jaq says `cannot index "web01" with "host"`. One case differs in substance: `{a: 1} | .[0]` is an error on jq and gojq and `null` on jaq.

Reading a missing field is not an error: `null | .host` is `null`. That is why a typo in a field name gives nulls rather than an error.

## 6. JSON inside a string

*The question:* "Read the JSON inside a string field" (asked in 2026 as a chained `jq | jq -r`).

APIs and logs often carry JSON as text inside a field. jq sees a string, and `.payload.host` fails with "Cannot index string". `fromjson` parses the text:

```jq
{"payload":"{\"host\":\"web01\",\"ram\":16}"} | .payload | fromjson | .ram
```

```json
16
```

`tojson` goes the other way.

## 7. jq and the shell

*The question:* the largest group by far: "remove the double quotes" (800 votes), "pass a bash variable to jq" (281 votes), "turn the output into a bash array or loop". In 2026 the same questions come from AI agents running jq in a shell.

- **Quotes.** jq prints JSON, so strings come out quoted. `-r` prints a string as raw text:

  ```bash
  jq -c '.host' hosts.jsonl   # "web01" "db01"
  jq -r '.host' hosts.jsonl   # web01 db01
  ```

- **A shell variable into the program.** Never paste it into the program text, where quoting breaks and a value can change the program. Pass it as a variable: `--arg` for text, `--argjson` for a number, boolean or JSON value.

  ```bash
  host=db01
  jq -c --arg h "$host" 'select(.host == $h) | .ram' hosts.jsonl     # 64
  jq -c --argjson min 32 'select(.ram > $min) | .host' hosts.jsonl   # "db01"
  ```

- **Output into a loop.** Print one value per line with `-r` and read lines. With `-c` and no `-r`, every string keeps its quotes:

  ```bash
  jq -r '.host' hosts.jsonl | while read -r h; do echo "got $h"; done   # got web01, got db01
  ```

  For several fields per line use `@tsv`, which escapes tabs and line breaks inside values: `jq -r '[.host, .ram] | @tsv'`. To build a shell command, `@sh` quotes a value for the shell: `jq -r '"echo " + (.host | @sh)'` gives `echo 'web01'`.

- **The program in single quotes.** In bash, write the program in single quotes so `$` and `"` reach jq untouched; pass values with `--arg` rather than closing the quotes. For anything longer than a line, put the program in a file and run `jq -f prog.jq`.

## 8. Membership and other slow patterns

*The question:* "Why is `IN` so slow?" (2026: 0.7 s in jq against 0.1 s in Python).

`IN(source)` tests whether the input is one of the values `source` gives, and runs `source` again for every input value: for a list of n names over m rows, n × m comparisons. To keep the rows whose key appears in another table, build an index once: that is a semi-join, `join_semi` in this library.

```bash
jq -c --slurp -L <dir> 'include "analytics"; join_semi([{host: "db01"}, {host: "app07"}]; .host; .host) | map(.host)' hosts.jsonl   # ["db01"]
```

`IN` is also missing from jaq (3.1.2: "undefined filter").

## 9. From the analytic question to the function

When the question is analytic, a named function replaces a hand-written `reduce`:

| The question | Function |
|---|---|
| how many, how much, the median, per key | `group_agg` with `mean`, `median`, `quantile_cont` |
| join two files on a key; keep the rows that match or do not | `join_left`, `join_inner`, `lookup`; `join_semi`, `join_anti` |
| dates with fractions of a second or an offset; local time; hours between | `parse_ts`, `local_time`, `format_local`, `hours_between` |
| the top N per group; the previous value; a running total | `window` with `row_number`, `rank_by`, `lag`, `running_sum` |
| JSON to CSV, TSV or a table; CSV into JSON | `to_csv(null)`, `to_tsv`, `to_table`; `from_csv` |
| flatten nested rows, and back | `flatten_fields`, `flatten_paths`, `unflatten_fields`, `unnest` |
| what changed between two versions | `diff_tables`, `diff_docs` |
| drop nulls and empty values everywhere | `drop_empty` (nulls only: `del(.. \| nulls)`) |

The README has the full table, the rules each function keeps and its cost.

## 10. For an agent that writes jq

A third of the 2026 Hacker News comments that name jq also name an AI model or agent, and the jq discussions include "the syntax is hard to remember". If you are an agent writing jq:

- **Look at the input first.** Run `profile` on a table, or print the keys and the type of a sample, before writing the program. Most wrong programs come from a wrong guess about the shape (section 5).
- **Reach for a named function before `reduce`.** A grouping, join or running total written by hand differs from run to run and is usually wrong about nulls; the library's functions are tested against DuckDB on five engines.
- **Collect before a table function.** Read JSON lines with `--slurp` or `[inputs]` (section 1).
- **Quote for the shell the program runs in.** Single quotes around the program, values through `--arg` and `--argjson` (section 7).
- **Use jq when it is there.** Writing a Python script to parse JSON that one jq line would read is slower to check and easier to get wrong.
- **Write the parentheses** around `//` in an assignment, and do not rely on `IN` if the program may run on jaq (sections 4 and 8).
