# Trying the skill on an agent

`questions.json` holds fifteen questions with made-up input and the expected answer. Give an agent only `skills/jq-analytics/` and `src/jq_analytics/analytics.jq`, ask it to answer each question by running jq with the library, and compare its answers with `expected`. Each question names the rule or the routing it tests. A wrong answer points at a gap in `SKILL.md`: fix the skill, not the question.

The record of each trial (date, model, score, what was changed in the skill afterwards) goes in the sprint spec's log.
