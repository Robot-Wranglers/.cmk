# fossil.cmk

`fossil.cmk` is a **ticket tracker over fossil, with a mutable body**.  A library plugin;
import it under whatever name you want the verbs to carry:

```Makefile
$(call import.module, file=fossil.cmk prefix=.cmk namespace=tkt plugin=1)
```

## Public surface

<hr class="section-rule lvl-3">

| Target | Purpose |
| --- | --- |
| `tkt.init` | create the tracker at the git root and install its schema and view page; idempotent |
| `tkt.new` | file a ticket: `title` required, stdin becomes the markdown description |
| `tkt.show/<uuid>` | one ticket as markdown: title, fields, description, then comments |
| `tkt.list` | markdown table; filter with `status=` and `tag=` |
| `tkt.search/<text>` | substring across titles, descriptions, and comments |
| `tkt.edit/<uuid>` | replace the description from stdin |
| `tkt.comment/<uuid>` | add a comment from stdin |
| `tkt.tag/<uuid>` | replace the tag set |
| `tkt.block/<uuid>` | replace what the ticket waits on |
| `tkt.set/<uuid>` | write one field, named by the `field` var |
| `tkt.close/<uuid>` | close, with stdin as the closing comment |
| `tkt.serve` / `tkt.stop` | the web ui, `port` defaults to 9080 |
| `tkt.run/<argv>` | any fossil command, comma-delimited |

## The mutable body

<hr class="section-rule lvl-3">

Fossil appends to a ticket field only when its name carries a leading plus.  The schema
this plugin installs adds two ordinary fields, `description` and `tags`, so setting either
one replaces it outright, while `icomment` stays the append-only comment log.

That split is the whole design.  A ticket reads as one current statement plus a history
beside it, and **no verb shuns an artifact or rebuilds the repository**, so none of them
can destroy history.  Earlier versions of a description stay reachable through
`tkt.run/ticket,history,<uuid>`.

The view page renders both the description and each comment as markdown, so tables, fenced
code, and links all work.  Cross-reference another ticket as `[](<uuid>)`, markdown link
format 8, where the url becomes the display text; the verbs rewrite a bare `[<uuid>]` into
that form on the way in.

## Cross-references

<hr class="section-rule lvl-3">

Two kinds, and they are stored differently.

**Blockers** are a declared relation, held in the `blockers` field as canonical ten-char
ids.  Fossil has no built-in dependency concept, so this is an added field like `tags`,
which is the extension the ticket schema is designed for.  Only the waits-on direction is
stored; `tkt.show` derives what a ticket blocks by asking which tickets list it, so the two
views cannot disagree.  Ids resolve when written, and an unknown or ambiguous one fails
there rather than becoming a dead reference.

```bash
echo 'a39d7663e6 0991582b19' | make tkt.block/896eb890
echo '' | make tkt.block/896eb890   # clear
```

**Prose references** are anything written as `[](<uuid>)` in a description or comment.
Fossil indexes these itself, in its `backlink` table, so they need no field and no verb.
`tkt.show` reports them under `Referenced by`.  Use these for "see also", and a blocker
only when the ticket cannot proceed until the other closes.

## Usage

<hr class="section-rule lvl-3">

```bash
# file one, with tags
cat repro.md | title='widget explodes' tags='compiler oop' make tkt.new

# correct the statement of the problem, leaving the discussion alone
cat rewritten.md | make tkt.edit/896eb890

# add to the discussion
printf 'Reproduced on 4.4.1 as well.\n' | make tkt.comment/896eb890

# find it again
make tkt.search/widget
tag=compiler make tkt.list

# read it in a browser
port=9000 make tkt.serve
```
