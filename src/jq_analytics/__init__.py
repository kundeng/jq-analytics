"""jq_analytics: the jq module analytics.jq (one file, its zone tables included), shipped as package data.

    import jq, jq_analytics
    jq.compile(jq_analytics.include() + "group_agg({g}; length)").input_value(rows).first()

The jq package has no -L option and an empty default search list, so the program itself names
the directory; include() writes that line. From the command line: jq -L "$(python -c
'import jq_analytics; print(jq_analytics.LIB_DIR)')" 'include "analytics"; ...'.
"""
from pathlib import Path

__version__ = "0.12.0"

LIB_DIR = Path(__file__).resolve().parent


def include(alias: str | None = None) -> str:
    """The line that loads the library: `include "analytics" {...}; ` or, with an alias,
    `import "analytics" as <alias> {...}; ` (functions then called as <alias>::name)."""
    meta = '{search: "' + str(LIB_DIR) + '"}'
    return f'import "analytics" as {alias} {meta}; ' if alias else f'include "analytics" {meta}; '
