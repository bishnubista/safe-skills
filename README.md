# safe-skills

Security scanner for LLM-powered applications. Detects vulnerabilities across prompt injection, data disclosure, tool misuse, agent trust boundaries, and more — using [SAFE-MCP](https://github.com/SAFE-MCP/safe-mcp) SAFE-T techniques as the primary taxonomy, with OWASP LLM/Agentic and agentic controls as secondary mappings.

Works natively in **Claude Code**, **Codex**, and **Cursor** through platform-specific adapters.

## Quick Start

Pick your platform:

**Claude Code** (plugin):

```bash
claude plugin add bishnubista/safe-skills
```

**Claude Code** (manual):

```bash
curl -fsSL https://raw.githubusercontent.com/bishnubista/safe-skills/main/scripts/remote-install.sh | bash -s -- --claude
```

**Codex:**

```bash
curl -fsSL https://raw.githubusercontent.com/bishnubista/safe-skills/main/scripts/remote-install.sh | bash -s -- --codex
```

**Cursor:**

```bash
curl -fsSL https://raw.githubusercontent.com/bishnubista/safe-skills/main/scripts/remote-install.sh | bash -s -- --cursor
```

**All platforms:**

```bash
curl -fsSL https://raw.githubusercontent.com/bishnubista/safe-skills/main/scripts/remote-install.sh | bash -s -- --all
```

**From source** (contributors):

```bash
git clone https://github.com/bishnubista/safe-skills.git && cd safe-skills
./scripts/install.sh
```

### Install Targets

| Platform | What Gets Installed | Location |
|----------|-------------------|----------|
| Claude Code | SKILL.md bundle + references | `~/.claude/skills/llm-vulnerability-scan/` |
| Codex | SKILL.md bundle + openai.yaml + references | `~/.agents/skills/llm-vulnerability-scan/` |
| Cursor | Rule file | `~/.cursor/rules/safe-skills-security-scan.md` |

Use `--force` to upgrade an existing install. Use `--symlink` for live-dev mode. Run `./scripts/install.sh --help` for all options.

## Usage

### Claude Code

```text
/safe-skills:scan              # Full scan (all severities)
/safe-skills:scan quick        # Quick scan (Critical + High only)
```

### Codex

```text
$llm-vulnerability-scan run a full SAFE-T-first scan for this repo
$llm-vulnerability-scan run a quick critical/high scan
```

### Cursor

Ask in chat:

```text
Scan this repo for LLM and MCP security issues using SAFE-T primary mapping.
```

### Auto-Discovery

The scanner activates automatically when you discuss:

- OWASP LLM security or prompt injection risks
- Agent safety audits or MCP security
- Tool poisoning, data disclosure, or privilege escalation

### Defaults

| Setting | Default | Override |
|---------|---------|----------|
| Scan type | Full (all severities) | Pass `quick` for Critical + High only |
| Scan scope | Repo (tracked files) | Pass `include-local-config` for untracked files |

## What Gets Scanned

The scanner runs three phases:

**Phase 1 — Discovery:** Detects project type, finds LLM SDK imports (OpenAI, Anthropic, LangChain, etc.), and locates agent/MCP configs.

**Phase 2 — Parallel Scan:** Six workers scan simultaneously by security theme:

| Worker | Theme | SAFE-T Techniques |
|--------|-------|-------------------|
| 1 | Injection and Goal Hijack | SAFE-T1102, SAFE-T1110, SAFE-T1401, SAFE-T1402, SAFE-T1001, SAFE-T1008 |
| 2 | Data Disclosure and Supply Chain | SAFE-T1502, SAFE-T1503, SAFE-T1505, SAFE-T1002, SAFE-T1003, SAFE-T1207, SAFE-T1004, SAFE-T1006, SAFE-T1009, SAFE-T1204, SAFE-T2107 |
| 3 | Output, Tool Misuse and Execution | SAFE-T1101, SAFE-T1105, SAFE-T1104, SAFE-T1106, SAFE-T1302, SAFE-T1103, SAFE-T1109, SAFE-T1205, SAFE-T1111, SAFE-T1303, SAFE-T1305 |
| 4 | Identity, Memory and RAG | SAFE-T2106, SAFE-T1304, SAFE-T1306, SAFE-T1308, SAFE-T1202, SAFE-T1206, SAFE-T1702 |
| 5 | Reliability, Trust and Inter-Agent | SAFE-T2105, SAFE-T1404, SAFE-T2102, SAFE-T1701, SAFE-T1705, SAFE-T1904 |
| 6 | Agentic Controls and Governance | AC01–AC05 (using SAFE-T evidence) |

**Phase 3 — Report:** Findings are sorted by severity and saved to `docs/security/llm-vulnerability-report.md`.

## Frameworks Covered

| Framework | Version | Role |
|-----------|---------|------|
| [SAFE-MCP](https://github.com/SAFE-MCP/safe-mcp) | v1.0 | Primary taxonomy — findings keyed by `SAFE-T####` |
| [OWASP LLM Top 10](https://genai.owasp.org/resource/owasp-top-10-for-llm-applications-2025/) | 2025 | Secondary mapping (`LLM01`–`LLM10`) |
| [OWASP Agentic Top 10](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/) | 2026 | Secondary mapping (`ASI01`–`ASI10`) |
| Agentic Controls (SAIF/NIST aligned) | N/A | Secondary mapping (`AC01`–`AC05`) |

## Report Format

Each finding includes:

- **SAFE-T ID** and human-readable title
- **Severity** (Critical / High / Medium / Low / Informational)
- **File path and line number** with code snippet
- **Secondary mappings** to OWASP LLM, OWASP Agentic, and Agentic Controls
- **Remediation guidance** with applicable SAFE-M mitigations

Example:

````markdown
### [SAFE-T1102] Prompt Injection - User input concatenated into prompt
- **File:** src/api/chat.ts:45
- **Severity:** Critical
- **Secondary:** LLM01, ASI01, AC02
- **Code:**
  ```ts
  const prompt = `You are a helper. User says: ${userInput}`
  ```
- **Issue:** User input directly interpolated into prompt without sanitization
- **Remediation:** Use parameterized prompt templates; validate/sanitize user input
- **Mitigations:** SAFE-M-1 (Control/Data Flow Separation), SAFE-M-5 (Content Sanitization)
````

The report also includes an executive summary, SAFE-T coverage table, OWASP/Agentic rollups, and a prioritized remediation roadmap.

## Project Structure

```text
safe-skills/
├── skills/
│   ├── claude-code/llm-vulnerability-scan/   # Claude Code adapter
│   │   ├── SKILL.md                          #   Skill definition (with allowed-tools)
│   │   └── references/                       #   Detection checklists
│   ├── codex/llm-vulnerability-scan/         # Codex adapter
│   │   ├── SKILL.md                          #   Skill definition (no allowed-tools)
│   │   ├── agents/openai.yaml                #   OpenAI agent metadata
│   │   └── references/                       #   Detection checklists (parity-enforced)
│   └── cursor/llm-vulnerability-scan/        # Cursor adapter
│       └── security-scan.md                  #   Rule file
├── commands/
│   └── scan.md                               # /scan slash command (Claude Code)
├── scripts/
│   ├── install.sh                            # Cross-platform installer
│   ├── remote-install.sh                     # Curl one-liner bootstrap
│   ├── generate-checksums.sh                 # Regenerate CHECKSUMS.sha256
│   ├── lint-skill.sh                         # Skill contract + parity checks
│   ├── validate-report.sh                    # Report schema validation
│   └── parity-smoke.sh                       # Cross-platform parity smoke tests
├── assets/
│   └── report-template.md                    # Report template with placeholders
├── .claude-plugin/plugin.json                # Claude plugin manifest
├── .cursor/rules/security-scan.md            # Project-level Cursor rule
├── .github/workflows/skill-quality.yml       # CI: shellcheck + lint + parity
├── CHECKSUMS.sha256                          # Integrity manifest
└── LICENSE                                   # Apache-2.0
```

## Contributing

Areas where help is needed:

- **Detection patterns** — Extend SAFE-T patterns in `skills/claude-code/llm-vulnerability-scan/references/` (CI enforces parity with Codex references)
- **Language support** — Add patterns for Go, Rust, Java, Ruby, PHP
- **SAFE-MCP coverage** — Map additional SAFE-MCP techniques to detection patterns
- **Testing** — Run scans against real-world LLM projects and report false positives/negatives

### Validation

```bash
./scripts/lint-skill.sh       # Skill contracts + cross-platform parity
./scripts/parity-smoke.sh     # Parity smoke tests against report artifacts
shellcheck scripts/*.sh       # Shell script linting
```

All three checks run in CI on every push and PR.

## License

[Apache-2.0](LICENSE)

## References

- [SAFE-MCP Framework](https://github.com/SAFE-MCP/safe-mcp) — Primary taxonomy source
- [OWASP LLM Top 10 (2025)](https://genai.owasp.org/resource/owasp-top-10-for-llm-applications-2025/)
- [OWASP Agentic Top 10 (2026)](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/)
- [Agent Skills Specification](https://agentskills.io/specification)
