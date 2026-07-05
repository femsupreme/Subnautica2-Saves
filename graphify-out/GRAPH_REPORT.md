# Graph Report - .  (2026-07-05)

## Corpus Check
- Corpus is ~7,649 words - fits in a single context window. You may not need a graph.

## Summary
- 54 nodes · 97 edges · 6 communities (5 shown, 1 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 1 edges (avg confidence: 0.95)
- Token cost: 0 input · 67,577 output

## Community Hubs (Navigation)
- [[_COMMUNITY_BackupRestore Documentation|Backup/Restore Documentation]]
- [[_COMMUNITY_Claude Bot CI Automation|Claude Bot CI Automation]]
- [[_COMMUNITY_backup-mac.sh Functions|backup-mac.sh Functions]]
- [[_COMMUNITY_CodeQL & Auto-Merge Workflows|CodeQL & Auto-Merge Workflows]]
- [[_COMMUNITY_backup-windows.ps1 Functions|backup-windows.ps1 Functions]]
- [[_COMMUNITY_SaveFriend Code Note|Save/Friend Code Note]]

## God Nodes (most connected - your core abstractions)
1. `backup-mac.sh script` - 9 edges
2. `die()` - 8 edges
3. `Lint backup scripts workflow` - 8 edges
4. `Fail()` - 7 edges
5. `backup-mac.sh` - 7 edges
6. `backup-windows.ps1` - 7 edges
7. `Restore flow (repo -> save folder)` - 6 edges
8. `README.md (Subnautica 2 Saves)` - 6 edges
9. `restore()` - 5 edges
10. `Run Claude Code step (anthropics/claude-code-action)` - 5 edges

## Surprising Connections (you probably didn't know these)
- `README.md (Subnautica 2 Saves)` --semantically_similar_to--> `Save Backups/<date>/ snapshot folders`  [INFERRED] [semantically similar]
  README.md → CLAUDE.md
- `PAT-over-GITHUB_TOKEN automation design` --rationale_for--> `secrets.BOT_GH_PAT (used in claude.yml)`  [EXTRACTED]
  CLAUDE.md → .github/workflows/claude.yml
- `shellcheck job` --references--> `backup-mac.sh`  [EXTRACTED]
  .github/workflows/lint.yml → CLAUDE.md
- `psscriptanalyzer job` --references--> `backup-windows.ps1`  [EXTRACTED]
  .github/workflows/lint.yml → CLAUDE.md
- `PAT-over-GITHUB_TOKEN automation design` --rationale_for--> `secrets.BOT_GH_PAT (used in lint.yml)`  [EXTRACTED]
  CLAUDE.md → .github/workflows/lint.yml

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Self-healing CI automation loop using BOT_GH_PAT** — github_workflows_lint_lint_backup_scripts_workflow, github_workflows_codeql_codeql_advanced_workflow, github_workflows_claude_claude_code_workflow, github_workflows_auto_merge_auto_merge_pr_workflow, claude_md_bot_gh_pat_rationale [EXTRACTED 1.00]
- **Workflows required to succeed before auto-merge** — github_workflows_auto_merge_auto_merge_job, github_workflows_lint_lint_backup_scripts_workflow, github_workflows_codeql_codeql_advanced_workflow [EXTRACTED 1.00]
- **Mac/Windows scripts kept behaviorally in sync for backup and restore flows** — claude_md_backup_mac_sh, claude_md_backup_windows_ps1, claude_md_backup_flow, claude_md_restore_flow [EXTRACTED 1.00]

## Communities (6 total, 1 thin omitted)

### Community 0 - "Backup/Restore Documentation"
Cohesion: 0.35
Nodes (13): backup.config (gitignored, machine-specific), backup.config.example (committed template), Backup flow (save folder -> repo), backup-mac.sh, backup-windows.ps1, Restore flow (repo -> save folder), Save Backups/<date>/ snapshot folders, Lint backup scripts workflow (+5 more)

### Community 1 - "Claude Bot CI Automation"
Cohesion: 0.22
Nodes (11): secrets.BOT_GH_PAT (used in claude.yml), Checkout repository step (claude.yml), Claude Code workflow, claude job, Co-authored-by trailer suppression via claude_args, Open a PR for Claude's branch step, Run Claude Code step (anthropics/claude-code-action), subnautica2-backup-bot identity (+3 more)

### Community 2 - "backup-mac.sh Functions"
Cohesion: 0.56
Nodes (9): check_branch(), check_no_rebase_in_progress(), configure(), die(), require_git(), require_repo(), restore(), backup-mac.sh script (+1 more)

### Community 3 - "CodeQL & Auto-Merge Workflows"
Cohesion: 0.24
Nodes (10): PAT-over-GITHUB_TOKEN automation design, auto-merge job, Auto-merge Claude PRs workflow, secrets.BOT_GH_PAT (used in auto-merge.yml), analyze job (CodeQL), secrets.BOT_GH_PAT (used in codeql.yml), CodeQL Advanced workflow, codeql-alert tracking issue label (+2 more)

### Community 4 - "backup-windows.ps1 Functions"
Cohesion: 0.54
Nodes (7): Fail(), Initialize-Configuration(), Invoke-Restore(), Test-GitAvailable(), Test-GitRepo(), Test-NoRebaseInProgress(), Test-OnBranch()

## Knowledge Gaps
- **7 isolated node(s):** `Open a PR for Claude's branch step`, `subnautica2-backup-bot identity`, `codeql-alert tracking issue label`, `ci-failure tracking issue label`, `backup.config.example (committed template)` (+2 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **1 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Lint backup scripts workflow` connect `Backup/Restore Documentation` to `Claude Bot CI Automation`, `CodeQL & Auto-Merge Workflows`?**
  _High betweenness centrality (0.207) - this node is a cross-community bridge._
- **Why does `notify-on-failure job` connect `Claude Bot CI Automation` to `Backup/Restore Documentation`?**
  _High betweenness centrality (0.137) - this node is a cross-community bridge._
- **Why does `Claude Code workflow` connect `Claude Bot CI Automation` to `CodeQL & Auto-Merge Workflows`?**
  _High betweenness centrality (0.112) - this node is a cross-community bridge._
- **What connects `Open a PR for Claude's branch step`, `subnautica2-backup-bot identity`, `Co-authored-by trailer suppression via claude_args` to the rest of the system?**
  _8 weakly-connected nodes found - possible documentation gaps or missing edges._