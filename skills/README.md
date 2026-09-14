# Skills

Agent skills used to build this project, published so you can reuse them.

A **skill** is a folder of instructions an AI coding agent loads on demand: a
`SKILL.md` with a `description` that tells the agent *when* the skill is
relevant, plus reference files it pulls in only once the task actually needs
them. Claude Code discovers skills under `.claude/skills/`; this repository
keeps the real folder here in `skills/` so it is easy to find and copy, with a
symlink at `.claude/skills/ipa-inspector` pointing back.

## `ipa-inspector`

Everything needed to build or extend a byte-level iOS `.ipa` inspector in
Swift — the knowledge behind Binary Explorer.

| File | Lines | What's in it |
|---|---|---|
| [`SKILL.md`](ipa-inspector/SKILL.md) | 104 | Entry point: when the skill applies, the `Core/` ↔ `UI/` split, and the no-dependencies constraint |
| [`references/formats.md`](ipa-inspector/references/formats.md) | 375 | Byte layouts: ZIP EOCD, central/local headers, ZIP64, deflate, path safety · Mach-O magics, headers, load commands, sections, FairPlay · code-signature SuperBlob `0xFADE0CC0`, CodeDirectory, CMS chain |
| [`references/macos-ui.md`](ipa-inspector/references/macos-ui.md) | 186 | The three SceneKit modes, squarified treemap, camera, lighting, annotations, the interaction contract, palette, resource previews |
| [`references/pitfalls.md`](ipa-inspector/references/pitfalls.md) | 169 | Hard-won gotchas in parsing, SceneKit, AppKit/SwiftUI and the Xcode project |

The parsers it describes are written from the format specifications — no
third-party packages and no shelling out to `unzip`, `otool` or `codesign`.
That is deliberate: the app is sandboxed, and spawning tools from a sandbox is
fragile.

## Using it in your own project

Copy the folder into your repo's skill directory:

```bash
git clone https://github.com/Viktorianec/BinaryExplorer.git
mkdir -p ~/your-project/.claude/skills
cp -R BinaryExplorer/skills/ipa-inspector ~/your-project/.claude/skills/
```

Drop it in `~/.claude/skills/` instead to make it available in every project on
your machine. The agent reads the `description` in `SKILL.md` to decide when to
load it, so no wiring is needed — just start a session and ask for something it
covers.

## Writing your own

The shape is minimal:

```
skills/
└── my-skill/
    ├── SKILL.md              # required: frontmatter + instructions
    └── references/           # optional: loaded only when needed
        └── whatever.md
```

`SKILL.md` needs YAML frontmatter with two keys:

```yaml
---
name: my-skill
description: What this does, and — crucially — when to use it.
---
```

The `description` is the only part always in context, so it carries the whole
routing decision: name the concrete triggers (formats, file types, task
shapes), not just the topic. Keep `SKILL.md` short and push detail into
`references/`, so a long specification costs nothing until a task reaches for
it.
