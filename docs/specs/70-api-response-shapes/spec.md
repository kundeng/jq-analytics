---
spec_id: 70-api-response-shapes
status: DRAFT
closed_as: null
since: 2026-11-19
until: null
epic: shapes
features: [api-envelopes-and-pages, graphql-connections, side-loaded-records, aggregation-buckets, results-of-several-calls, type-outline, merge-documents]
supersedes: []
superseded_by: null
depends_on: [65-common-question-gaps]
anchors: [05-shapes]
---

# 70 API response shapes

## Requirements

### Scope

The commonest source of JSON for analysis is the reply to an API call, and the shapes design has no row for it: its sources are a nested document, an object keyed by id, a nested tree, YAML and an event log. The owner, reviewing the design (2026-11-19): data sources dictate the data types, and GraphQL, APIs that are not very RESTful, and several related REST calls are missing. An API reply is a source in the design's sense: it has to be unwrapped into a shape before a function can use it, and each kind of API wraps rows its own way.

| Source | Looks like | Example APIs |
|---|---|---|
| envelope and pages | rows under a key, with a link, cursor or offset to the next page | ServiceNow `{"result": [...]}`, Microsoft Graph `{"value": [...], "@odata.nextLink": ...}`, many `{"data": [...], "meta": {...}}` |
| GraphQL connection | `data.<path>.edges[].node` with `pageInfo`; connections inside nodes; an `errors` array beside partial `data` | GitHub, Shopify, most GraphQL APIs |
| side-loaded records | rows pointing to related records by type and id, the related records given once in `included` | JSON:API, normalized REST and front-end stores |
| aggregation buckets | nested `buckets` arrays, one level per grouping | Elasticsearch, OpenSearch, some metrics APIs |
| RPC replies | a batch of replies matched to requests by `id`; a result or an error each | JSON-RPC, many internal "action" endpoints |
| several related calls | a list call, then one call per item, or calls to several systems, each reply kept with the request that made it | list-then-detail, parent-then-children, tickets plus CMDB plus logs |

### Requirements

- **R1. The design.** `docs/design/05-shapes.md` gains these six as sources, each with a made-up but faithful sample, the shape it becomes, the unwrap that gets it there, and the mistake people make with it (a row repeated or lost across pages, a nested connection flattened into a cross product, an `errors` array ignored, a side-loaded record looked up by id alone when ids repeat across types).
- **R2. Pages.** `rows_from_pages(rows; key)`: an array of page replies into one table, `rows` saying where the rows are in a page (`.result`, `.value`, `.data`); a key that appears on two pages is an error naming it, since a page boundary that moved between calls is the usual cause.
- **R3. GraphQL.** `rows_from_connection(path)`: the nodes of a connection as rows, each with its cursor; a page array of replies is accepted; a reply with a non-empty `errors` array is an error that quotes the first message unless asked to keep partial data.
- **R4. Side-loaded records.** `resolve_refs($included; $as)`: each relationship reference `{type, id}` in a row replaced by the included record of the same type and id, under `$as`; a reference with no included record stays as it is, reported in a field; type and id together are the key.
- **R5. Buckets.** `rows_from_buckets($levels)`: nested aggregation buckets into one row per leaf bucket, a column per level named by `$levels`, with the leaf's counts and metrics; a missing level is an empty table, not an error.
- **R6. Several calls.** `rows_from_calls`: an array of `{request, response}` records (the form an audit record keeps a call in) into one table, each row carrying the request fields it came from, so a list call and its detail calls can be joined on them. RPC batches are the same form and join on `id` with the existing joins.
- **R8. Type outline.** `type_outline`: the structure of any document with types instead of values (an array's items merged into one outline, a field's types listed when they differ, how often a field is present), the first look at an unfamiliar reply before choosing its unwrap. Asked for in jq #3540 (2026); `shape` gives row counts and field names per table, which is not this.
- **R9. Merge documents.** `merge_docs($other; $arrays)`: a deep merge of two documents where arrays are combined by `"concat"`, `"union"` (without duplicates) or `"replace"`; jq's `*` always replaces arrays. The most-viewed jq question of the last year asks for this (Unix & Linux 801994, 2,002 views).
- **R7.** Each function: input check, read-out note, README entry, skill row, cases including the mistake its section names; DuckDB answers where DuckDB can express the same unwrap (`unnest` of JSON).

### Out of scope

Making the calls (fetching, auth, retry and paging loops belong to the caller: an audited fetch, a flow's replay step); XML and SOAP; GraphQL schema introspection.

## Design

Written when the sprint opens. Before any function: collect one real reply of each kind the owner uses (ServiceNow, Microsoft Graph, Splunk; a GraphQL source if he has one; public samples for the rest), reduce each to a made-up sample of the same shape, and write R1 first. A function is added only where the unwrap is more than a line of plain jq or where the plain line has a known trap; otherwise the design section shows the plain jq.

## Tasks

- [ ] 1. Samples and the design section (R1); a decision per source: function or plain jq.
- [ ] 2. The functions R2 to R6 that the decision keeps, and R8 and R9, with cases.
- [ ] 3. Read-out notes, README, skill, feature matrix; version 0.16.0.

## Log

- 2026-11-19. Drafted from the owner's design comment that API replies, GraphQL and several related calls are missing from the shapes.
- 2026-11-19. R8 and R9 added from the survey of the last twelve months (owner's go-ahead).
