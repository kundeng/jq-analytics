---
spec_id: 70-alpha-readiness
status: DRAFT
closed_as: null
since: 2026-11-19
until: null
epic: release
features: [readme-opener, ci-engine-matrix, one-line-install, playground-demo, authorship-note, cookbook-recipe]
supersedes: []
superseded_by: null
depends_on: [65-common-question-gaps]
anchors: []
---

# 70 Alpha readiness

## Requirements

### Scope

What a first-time reader needs before the library is announced (sprint 75), from the places it will be announced: Show HN asks for something people can run without signing up and excludes quickly generated one-offs; r/commandline polices AI-generated projects; the awesome-jq list and the jq wiki Modules page are where people search.

### Requirements

- **R1. README opener.** The README opens with three before/after examples, each a common question (a join of two files, a group with a median, a time-zone or "who held it" case): the plain-jq answer, the library's, and the output.
- **R2. Install in one line.** Download `analytics.jq` from a tagged release and `include "analytics"` with `-L`; also the Python package.
- **R3. CI.** GitHub Actions runs the cases on jq 1.7.1, jq 1.8.x, gojq, jaq and the Python package on every push; the README shows the matrix with exact versions and the badge.
- **R4. A demo with no install**: a link to a jq playground with the library loaded, or a short recording.
- **R5. How it was made.** A short README section: written with an AI coding agent, every function checked against DuckDB on five engines, a code read-out of every definition, reviewed by the author.
- **R6. A Cookbook recipe** for the jq wiki that uses the library on one common question.
- **R7. Release notes** for the alpha and a CHANGELOG from 0.1.0.

## Tasks

- [ ] 1. README opener (R1) and install (R2).
- [ ] 2. CI matrix (R3).
- [ ] 3. Demo (R4).
- [ ] 4. Authorship section (R5), Cookbook recipe draft (R6), CHANGELOG and release notes (R7).
- [ ] 5. Tag the alpha.

## Log

- 2026-11-19. Drafted from the survey of announcement places; the alpha also waits for the end of the owner's review.
