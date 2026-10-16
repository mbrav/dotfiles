---
name: wiki-reindex
description: >
  Audit and repair the Obsidian wiki knowledge base. Finds orphan notes not linked from
  their section index, sections missing from the root wiki/_index.md, and cross-section
  link opportunities between related topics — then auto-fixes everything in place.
  Use this skill whenever the user says "reindex", "audit the wiki", "check for orphans",
  "find missing links", "lint the wiki", "improve organization", "check wiki structure",
  or asks to go through the vault and find potential links or improve organization.
  Also trigger proactively when the user has just added several new notes or sections and
  the wiki may have drifted out of sync.
---

# Wiki Reindex

Audit the `wiki/` knowledge base for structural gaps and missing cross-links, then apply all fixes automatically.

**Prerequisites:** The obsidian CLI is used throughout this skill for backlink lookups, content search, and appending fixes. Obsidian must be open with the vault active. If `obsidian` commands fail, fall back to the shell-only methods noted in each step.

## What this skill does

1. **Orphan check** — find notes not referenced in their section `_index.md`
2. **Root index check** — find section directories absent from `wiki/_index.md`
3. **Cross-link discovery** — identify related notes across sections that should link to each other but don't
4. **Auto-fix** — apply all changes directly to the files

## Vault conventions to follow

- Every directory under `wiki/` has a `_index.md` with `type: moc` frontmatter
- Internal links use wikilinks: `[[note-name]]` or `[[path/_index|Display Name]]`
- Cross-section links use path-qualified wikilinks: `[[rag/vector-indexes]]`, `[[wiki/postgres/_index|Postgres]]`
- Study notes end with a `## See Also` section (bullet list of wikilinks)
- Index files use a `## Related` section for cross-section pointers
- Never reference files under `raw/` from wiki notes — `raw/` is a staging area only

## Step 1 — Structural audit

### 1a. Enumerate notes and check for missing section indexes

```bash
# All wiki notes
find wiki/ -name "*.md" | sort

# Missing from root index
root="wiki/_index.md"
for dir in wiki/*/; do
  section=$(basename "$dir")
  grep -q "$section" "$root" || echo "MISSING FROM ROOT: $section"
done
```

For sections with subdirectories (e.g. `wiki/courses/lpic1/`, `wiki/trading/journal/`), recurse one level deeper — check that the parent `_index.md` references those subdirectories.

### 1b. Find orphan candidates with grep

```bash
# Orphan candidates: notes not mentioned by name in their section _index.md
for dir in wiki/*/; do
  section=$(basename "$dir")
  index="${dir}_index.md"
  [ ! -f "$index" ] && echo "MISSING INDEX: $section" && continue
  for note in "${dir}"*.md; do
    [ ! -f "$note" ] && continue
    [ "$(basename "$note")" = "_index.md" ] && continue
    name=$(basename "$note" .md)
    grep -q "$name" "$index" || echo "ORPHAN CANDIDATE: wiki/$section/$name"
  done
done
```

### 1c. Verify orphan candidates with backlinks

`grep` only checks the section index by note filename. Obsidian's backlink graph catches aliased links, path-qualified links, and links in other files that point back to the note. For each orphan candidate, verify it truly has no inbound links:

```bash
obsidian backlinks path="wiki/<section>/<note>.md"
```

If backlinks exist (even from outside the section index), the note isn't truly orphaned — it's just the index that's missing the entry, which is still worth fixing. If it has zero backlinks across the entire vault, it's a priority orphan. Note both states in your findings.

## Step 2 — Cross-link discovery

### 2a. Use obsidian search to find actual content connections

Rather than reading every `_index.md` and reasoning from section names alone, use `obsidian search` to surface notes that genuinely discuss cross-cutting topics. Run targeted queries for each candidate relationship:

```bash
# Examples — run queries relevant to sections that exist in the vault
obsidian search query="pgvector OR tsvector OR vector search" limit=20
obsidian search query="Zabbix OR alerting OR monitoring" limit=20
obsidian search query="WireGuard OR netbird OR VPN" limit=20
obsidian search query="Pulumi OR IaC OR infrastructure as code" limit=20
obsidian search query="LXC OR proxmox OR hypervisor" limit=20
```

Results tell you which notes across sections actually contain the content — not just which sections you think might be related. For each result in an unexpected section, read the note to decide if a cross-link is warranted.

### 2b. Seed queries from the known relationship map

Use this as a starting map of likely relationships, but let the search results extend or contradict it:

| Section | Query terms to try | Likely links to |
|---------|-------------------|-----------------|
| `rag/` | `pgvector tsvector pg_textsearch` | `postgres/` |
| `rag/` | `inference embedding model` | `llm/` |
| `postgres/` | `vector similarity full-text search` | `rag/` |
| `postgres/` | `Zabbix database migration` | `monitoring/` |
| `postgres/` | `RDS Aurora managed` | `aws/` |
| `monitoring/` | `k8s kubernetes alerts` | `kubernetes/` |
| `networking/` | `WireGuard VPN overlay` | `netbird/` |
| `netbird/` | `Pulumi provider` | `pulumi/` |
| `kubernetes/` | `LXC proxmox node` | `proxmox/` |

### 2c. Verify before linking

For each candidate cross-link surfaced by search, read both notes:

```bash
obsidian read path="wiki/<section-a>/<note>.md"
obsidian read path="wiki/<section-b>/<note>.md"
```

A cross-link is worth adding only if a reader finishing one note would naturally want to continue with the other. Don't add links just because topics share a keyword.

## Step 3 — Apply fixes

### Orphan in section `_index.md`

Read the note to craft an accurate one-line description, then edit the index file:

```bash
obsidian read path="wiki/<section>/<note>.md"
```

Add a bullet in the appropriate section of the index using the Edit tool:

```markdown
- [[note-file-name|Human Readable Title]] — one-line description
```

### Missing section in root `wiki/_index.md`

Add a bullet in `## Sections` using the Edit tool:

```markdown
- [[section/_index|Section Name]] — brief description of topics covered
```

### Missing cross-link in a study note (`type: study`)

If the note already has a `## See Also` section, insert into it with the Edit tool.

If there is no `## See Also` section, append it directly via obsidian CLI (avoids a read-then-edit round-trip):

```bash
obsidian append path="wiki/<section>/<note>.md" content="\n## See Also\n\n- [[target-note|Display text]] — why this is relevant"
```

### Missing cross-link in an index file (`type: moc`)

Add to the `## Related` section using the Edit tool (create it before `## See Also` if it doesn't exist).

## Step 4 — Report

After applying all fixes, output a concise summary:

```
## Wiki Reindex Complete

**Orphans fixed:** N
**Root index entries added:** N  
**Cross-links added:** N

### Changes made
- wiki/section/note.md → added to section/_index.md
- wiki/rag/bm25-full-text-search.md → added link to [[use-tsvector-for-full-text-search]]
- ...
```

If nothing needed fixing, say so explicitly — a clean result is useful information.
