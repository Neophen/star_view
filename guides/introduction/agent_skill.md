# Agent skill

StarView 0.6.0 includes a portable skill in its source checkout and Hex package at
`skills/datastar/`. Copy the **whole folder**, including `references/`, into
your agent's skill directory. The skill uses ordinary `SKILL.md` frontmatter
and Markdown; it does not require a specific model, MCP server or credentials.

| Agent | Project location | Personal location |
| --- | --- | --- |
| Codex | `.agents/skills/datastar/` | `~/.agents/skills/datastar/` |
| Claude Code | `.claude/skills/datastar/` | `~/.claude/skills/datastar/` |
| Other skill-capable agents | Their documented skills directory | Their documented skills directory |

These locations follow the official [Codex skill documentation](https://developers.openai.com/codex/skills/)
and [Claude Code skill documentation](https://code.claude.com/docs/en/skills).
Review an existing skill with the same name before replacing it; duplicate
installations are not automatically merged.

From a StarView source checkout, a project installation for Codex is:

```sh
mkdir -p /path/to/your/app/.agents/skills
cp -R skills/datastar /path/to/your/app/.agents/skills/
```

For Claude Code, use `.claude/skills` as the destination. From a fetched Hex
dependency, the source folder is normally `deps/star_view/skills/datastar`.
Use the folder from the version you actually installed. Other agents can read
the same manifest and references according to their own skill-loading support;
the optional `agents/openai.yaml` only supplies Codex UI metadata.

The skill covers Datastar/Rocket ownership, StarView request lifecycles, native
`~STAR`, checked event references, live rendering, drafts and performance.
It distinguishes released APIs from experimental additions and does not grant
permission to migrate existing screens, provision services or publish changes.

Keep project-specific conventions and service access in your own repository
instructions. The shared skill contains no application credentials or
application-specific configuration. Update it alongside API changes so a
copied version explains the guarantees of its matching SDK.

The bundled skill and checked-event additions require StarView 0.6.0 or later.
Use `{:star_view, "~> 0.6.0"}` for this release; they are absent from 0.5.0.
