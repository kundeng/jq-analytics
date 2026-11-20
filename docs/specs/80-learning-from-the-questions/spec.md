---
spec_id: 80-learning-from-the-questions
status: DRAFT
closed_as: null
since: 2026-11-19
until: null
epic: teaching
features: [questions-survey-page, jq-model-primer]
supersedes: []
superseded_by: null
depends_on: [75-core-jq-and-engines]
anchors: []
---

# 80 Learning from the questions people ask

## Requirements

### Scope

Learning is the library's first purpose. The survey of 2026-11-19 (Stack Overflow's 200 highest-voted jq questions and its 60 most-linked, jq's issues by reactions and comments, the jq wiki, Hacker News) found that most traffic is about two things no function can fix: getting jq to work with the shell (quoting, raw output, bash variables in and out; up to 823,000 views a question) and jq's own model (a filter runs once per value; `.[]` makes many values from one; `select` drops a value rather than returning false; picking and filtering fields). The library's analytic answers only help a reader who has that model.

### Requirements

- **R1. The survey, in the repo.** `docs/research/questions-2026-11-19.md`: how it was done (sources, queries, counts, what was not reachable), the twenty kinds of question with their evidence, and what the library does for each, so the claims in the README can be checked. Public sources only.
- **R2. A primer.** `docs/primer.md`, before any library function: the five ideas behind most of those questions (one value in, one or many out; paths and `select`; building objects and arrays; `reduce` and variables; jq and the shell), each with the question that shows it, a small run and the common wrong version. It links each analytic question to the function that answers it.
- **R3.** The README's "One value in" rule and the tutorial outline point to the primer.

### Out of scope

The tutorial chapters themselves and the articles (they follow the alpha).

## Tasks

- [ ] 1. The survey page (R1), checked against the raw pulls.
- [ ] 2. The primer (R2), every run checked on the engines.
- [ ] 3. Links (R3).

## Log

- 2026-11-19. Drafted after the owner asked how the survey was done and what the challenges are; the survey had been used before it was discussed with him.
