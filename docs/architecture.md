# Architecture: safe-skills

> A comprehensive guide to why this project exists, what it does, and how it works — from problem space to runtime execution.

**Last updated:** 2026-02-11

---

## Table of Contents

- [Why — The Problem](#why--the-problem)
- [What — The Solution](#what--the-solution)
- [How — Architecture](#how--architecture)
  - [Distribution Architecture](#distribution-architecture)
  - [Runtime Architecture](#runtime-architecture)
  - [Component Reference](#component-reference)
  - [Worker Architecture](#worker-architecture)
  - [Data Flow](#data-flow)
  - [Key Design Patterns](#key-design-patterns)
  - [Design Decisions](#design-decisions)

---

## Why — The Problem

### LLM apps ship with zero security tooling

Developers building with OpenAI, Anthropic, LangChain, and MCP servers have **no equivalent of ESLint, Semgrep, or SonarQube** for LLM-specific vulnerabilities. When a developer writes:

```typescript
const prompt = `You are a helper. User says: ${userInput}`;
```

No existing linter flags this as a prompt injection vulnerability — yet it's as dangerous as unsanitized SQL concatenation was in 2005. Traditional SAST tools parse ASTs and match syntax patterns; they have no concept of "this string becomes an LLM system prompt" or "this tool definition grants excessive agency."

### Three frameworks exist, but nobody unifies them

The security community has produced three complementary frameworks, each answering a different question:

| Framework | Question it answers | Depth |
|-----------|-------------------|-------|
| [OWASP LLM Top 10 (2025)](https://genai.owasp.org/resource/owasp-top-10-for-llm-applications-2025/) | "What risk categories exist when building with LLMs?" | 10 high-level categories |
| [OWASP Agentic Top 10 (2026)](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/) | "What additional risks exist when LLMs act autonomously?" | 10 agent-specific categories |
| [SAFE-MCP](https://github.com/SAFE-MCP/safe-mcp) | "What specific attack techniques exist and how do I detect/mitigate each?" | 81 TTPs + 48 mitigations (MITRE ATT&CK methodology) |

These frameworks are published as PDFs, web pages, and GitHub repos. None provide runnable tooling. A developer who reads all three still has to manually audit their codebase file-by-file.

### AI coding agents are the ideal delivery vehicle

Developers already use Claude Code, Cursor, and Codex to *write* their LLM apps. The same agent that writes the code can scan it for security issues — no CI pipeline, no separate tool, no context switching. The agent has:

- Full codebase access via built-in tools (Read, Grep, Glob)
- Semantic understanding of code (can reason about data flow, not just pattern match)
- Parallel execution capability (can spawn multiple scan workers)
- Native output formatting (generates structured markdown reports)

---

## What — The Solution

**safe-skills** is a **Claude Code plugin** (and cross-agent skill) that scans LLM application code for security vulnerabilities. It unifies all three security frameworks into a single automated scan with structured reporting.

### Framework Integration Model

The three frameworks operate at different abstraction levels and complement each other like a layered defense:

```text
┌─────────────────────────────────────────────────────────────┐
│  OWASP LLM Top 10 (2025)                                   │
│  HIGH LEVEL: "What risk categories exist?"                  │
│  10 categories: Prompt Injection, Excessive Agency, ...     │
├─────────────────────────────────────────────────────────────┤
│  OWASP Agentic Top 10 (2026)                               │
│  AGENT FOCUS: "What risks do autonomous agents introduce?"  │
│  10 categories: Goal Hijack, Tool Misuse, Rogue Agents, ...│
├─────────────────────────────────────────────────────────────┤
│  SAFE-MCP Framework                                         │
│  GRANULAR: "How exactly do attackers exploit these?"        │
│  81 specific TTPs across 14 tactics, 48 mitigations        │
│  MITRE ATT&CK methodology adapted for MCP ecosystem        │
├─────────────────────────────────────────────────────────────┤
│  Agentic Controls Checklist (AC01–AC05)                     │
│  CROSS-CUTTING: "What guardrails should be in place?"       │
│  Least privilege, guardrails, validation, approvals,        │
│  observability & budgets                                    │
└─────────────────────────────────────────────────────────────┘
```

### SAFE-MCP Integration: SAFE-T-First (Current)

As of **2026-02-11**, the scanner uses SAFE-MCP `SAFE-T####` as the primary taxonomy and treats OWASP/Agentic/AC as secondary rollups.

Current integration model:

| Dimension | Current behavior |
|-----------|------------------|
| Primary finding key | `SAFE-T####` |
| Secondary mapping | `LLM##`, `ASI##`, `AC##` |
| Coverage reporting | SAFE-T coverage table + secondary framework rollup |
| Worker model | 6 themed workers clustered by SAFE-T techniques |

Example finding shape:

```markdown
### [SAFE-T1102] Prompt Injection - User input concatenated into prompt
- **File:** src/api/chat.ts:45
- **Severity:** Critical
- **Secondary:** LLM01, ASI01, AC02
- **Mitigations:** SAFE-M-1 (Control/Data Flow Separation), SAFE-M-5 (Content Sanitization)
```

Historical note: earlier iterations used OWASP categories as the primary organizer and SAFE-T as enrichment. That model is now superseded by the SAFE-T-first contract.

### Full Category Coverage

The scanner covers **25 categories** total across all frameworks:

| ID Range | Framework | Count | Categories |
|----------|-----------|-------|------------|
| LLM01–LLM10 | OWASP LLM Top 10 | 10 | Prompt Injection, Sensitive Info Disclosure, Supply Chain, Data Poisoning, Improper Output, Excessive Agency, Prompt Leakage, Vector/Embedding, Misinformation, Unbounded Consumption |
| ASI01–ASI10 | OWASP Agentic Top 10 | 10 | Goal Hijack, Tool Misuse, Identity Abuse, Agentic Supply Chain, Code Execution, Memory Poisoning, Insecure Inter-Agent, Cascading Failures, Trust Exploitation, Rogue Agents |
| AC01–AC05 | Agentic Controls | 5 | Least-Privilege Tooling, Input Guardrails, Tool I/O Validation, Human-in-the-Loop, Observability & Budgets |

Each category maps to specific SAFE-MCP technique IDs. The full cross-reference is maintained in the worker checklists under `skills/*/llm-vulnerability-scan/references/`.

---

## How — Architecture

### Distribution Architecture

#### Plugin Format

The project is packaged as a **Claude Code plugin** — a format that bundles skills, commands, and scripts into a single installable unit. This was modeled after the [Vercel Claude Code plugin](https://github.com/vercel/vercel-deploy-claude-code-plugin), with one key difference:

```text
Vercel Plugin                       safe-skills Plugin
├── .claude-plugin/                 ├── .claude-plugin/
│   ├── plugin.json                 │   └── plugin.json
│   └── marketplace.json            │
├── commands/                       ├── commands/
│   ├── deploy.md                   │   └── scan.md
│   ├── logs.md                     │
│   └── setup.md                    │
├── skills/                         ├── skills/
│   ├── deploy/SKILL.md             │   └── llm-vulnerability-scan/
│   ├── logs/SKILL.md               │       ├── SKILL.md
│   └── setup/SKILL.md              │       └── references/
│                                   │           ├── owasp-llm-checklist.md
│                                   │           └── agentic-controls.md
├── MCP server (mcp.vercel.com) ←── │   [None — local analysis only]
│                                   ├── scripts/
│                                   │   └── install.sh
│                                   ├── assets/
│                                   │   └── report-template.md
├── README.md                       ├── README.md
└── LICENSE                         └── LICENSE
```

**Why no MCP server:** Vercel needs an MCP server because it calls the Vercel API (deployments, logs, environment variables). Our scanner only reads local files using the agent's built-in tools (Read, Grep, Glob). An MCP server would add infrastructure complexity with zero benefit.

**Why a plugin (not just a standalone skill):** The plugin format bundles skills + commands + scripts into one installable unit. The `/scan` command provides explicit invocation. The skill provides auto-discovery. The install script provides cross-agent reach.

#### Cross-Agent Reach

The skill uses the [Agent Skills open standard](https://agentskills.io/specification) (`SKILL.md` format), natively supported by all three major AI coding agents:

| Agent | Install Method | Discovery Path | Invocation |
|-------|---------------|----------------|------------|
| **Claude Code** | `claude plugin install safe-skills` | Native plugin system | `/safe-skills:scan` or auto-discover |
| **Cursor** (v2.4+) | `./scripts/install.sh` | `~/.cursor/skills/` | `/llm-vulnerability-scan` or auto-discover |
| **Codex** | `./scripts/install.sh` | `~/.agents/skills/` | `$llm-vulnerability-scan` or auto-discover |

The install script (`scripts/install.sh`) installs an immutable copy by default (with checksum verification) to each agent's discovery path. It supports `--symlink` for local development, `--symlink --no-verify` for rapid local iteration, and `--force` to replace an existing install during upgrades.

#### Project File Structure

```text
safe-skills/
├── CHECKSUMS.sha256                          # Integrity manifest for installer verification
├── .github/workflows/
│   └── skill-quality.yml                     # CI lint + optional parity smoke job
├── .claude-plugin/
│   └── plugin.json                          # Plugin manifest (name, version, entry points)
├── .cursor/rules/
│   └── security-scan.md                     # Cursor adapter routing
├── commands/
│   └── scan.md                              # /scan slash command (delegates to SKILL.md)
├── skills/
│   ├── claude-code/llm-vulnerability-scan/  # Claude Code adapter
│   │   ├── SKILL.md                         # Orchestrator skill (~250 lines)
│   │   └── references/
│   │       ├── safe-t-checklist.md          # Primary SAFE-T technique checklist
│   │       ├── owasp-llm-checklist.md       # Secondary OWASP rollup mapping
│   │       └── agentic-controls.md          # Agentic control checklist AC01–AC05
│   ├── codex/llm-vulnerability-scan/        # Codex adapter
│   │   ├── SKILL.md
│   │   ├── agents/openai.yaml              # Codex agent metadata
│   │   └── references/                      # Same checklists as claude-code
│   └── cursor/llm-vulnerability-scan/       # Cursor adapter
│       └── security-scan.md                 # Cursor rule-based routing
├── scripts/
│   ├── install.sh                           # Cross-agent installer (copy default, symlink optional)
│   ├── remote-install.sh                    # Curl one-liner installer
│   ├── generate-checksums.sh                # Regenerates CHECKSUMS.sha256
│   ├── lint-skill.sh                        # Skill contract checks
│   ├── validate-report.sh                   # Report schema checks
│   └── parity-smoke.sh                      # Cross-platform parity checks
├── assets/
│   └── report-template.md                   # Markdown report template with placeholders
├── docs/
│   └── architecture.md                      # This document
├── README.md
└── LICENSE
```

### Runtime Architecture

The scanner executes in a **3-phase pipeline**: Discovery, Parallel Scan, and Report Generation.

```text
User invokes: /safe-skills:scan [quick]

         Phase 1: DISCOVERY (Orchestrator)
         ┌──────────────────────────────────┐
         │  1. Detect project type           │
         │  2. Find LLM SDK imports          │
         │  3. Locate agent & MCP configs    │
         │  4. Find prompt templates & RAG   │
         │  5. Find agentic control points   │
         │  6. Build categorized FILE        │
         │     MANIFEST for workers          │
         └──────────────┬───────────────────┘
                        │ manifest
         Phase 2: PARALLEL SCAN (6 Workers)
         ┌──────────────┴───────────────────────────────────┐
         │  All 6 launched in a single parallel call        │
         │                                                   │
    ┌────┴─────┐  ┌──────────┐  ┌──────────┐               │
    │ Worker 1 │  │ Worker 2 │  │ Worker 3 │               │
    │ Injection│  │ Data &   │  │ Output,  │               │
    │ & Goal   │  │ Supply   │  │ Tool     │               │
    │ Hijack   │  │ Chain    │  │ Misuse   │               │
    │          │  │          │  │ Safety   │               │
    │ SAFE-T11 │  │ SAFE-T15 │  │ SAFE-T11 │               │
    │ SAFE-T14 │  │ SAFE-T10 │  │ SAFE-T13 │               │
    │ SAFE-T10 │  │ SAFE-T12 │  │ SAFE-T12 │               │
    │          │  │ SAFE-T21 │  │          │               │
    └──────────┘  └──────────┘  └──────────┘               │
    ┌──────────┐  ┌──────────┐  ┌──────────┐               │
    │ Worker 4 │  │ Worker 5 │  │ Worker 6 │               │
    │ Identity,│  │ Reliab.  │  │ Agentic  │               │
    │ Memory & │  │ Trust &  │  │ Controls │               │
    │ RAG      │  │          │  │ & Gov.   │               │
    │          │  │          │  │          │               │
    │ SAFE-T21 │  │ SAFE-T21 │  │ AC01     │               │
    │ SAFE-T13 │  │ SAFE-T14 │  │ AC02     │               │
    │ SAFE-T12 │  │ SAFE-T17 │  │ AC03     │               │
    │ SAFE-T17 │  │ SAFE-T19 │  │ AC04     │               │
    │          │  │          │  │ AC05     │               │
    │          │  │          │  │          │               │
    └──────────┘  └──────────┘  └──────────┘               │
         │                                                   │
         └──────────────┬───────────────────────────────────┘
                        │ structured findings
         Phase 3: REPORT GENERATION (Orchestrator)
         ┌──────────────┴───────────────────┐
         │  1. Collect all worker findings   │
         │  2. Deduplicate overlapping hits  │
         │  3. Sort: Critical → Info         │
         │  4. Fill report-template.md       │
         │  5. Add AC01–AC05 summary table   │
         │  6. Add SAFE-T coverage +         │
         │     secondary rollup tables       │
         │  7. Save to docs/security/        │
         │  8. Display executive summary     │
         └──────────────────────────────────┘
```

### Component Reference

#### plugin.json

The plugin manifest registers the skill and command with Claude Code:

```json
{
  "name": "safe-skills",
  "version": "0.1.0",
  "description": "Security scanning skills for LLM-powered applications...",
  "skills": "./skills/",
  "commands": "./commands/"
}
```

#### commands/scan.md

A thin wrapper that delegates to the skill. Provides the explicit `/scan` invocation point:

```markdown
1. Select scan mode deterministically (`quick` -> Quick, otherwise Full)
2. Select scope deterministically (repo scope by default; local config only on explicit request)
3. Run the `llm-vulnerability-scan` skill and generate SAFE-T keyed findings
4. Save report to `docs/security/llm-vulnerability-report.md`
5. Display executive summary with Severity, Overall Risk, Scan Type, and Scan Scope
```

#### SKILL.md (Orchestrator)

The main skill file (~250 lines). Contains the 3-phase pipeline instructions, worker dispatch templates, and report generation logic. Follows the Agent Skills specification:

- Frontmatter: `name`, `description` (starts with "Use when...")
- Under 500 lines (progressive disclosure)
- Name matches parent directory (`llm-vulnerability-scan`)

#### references/safe-t-checklist.md

Primary reference file containing SAFE-T technique groupings and worker-specific detection patterns. Each worker section includes:

- Primary SAFE-T technique IDs
- Secondary rollup mapping hints (`LLM##`, `ASI##`, `AC##`)
- Baseline remediation guidance

#### references/agentic-controls.md

Checklist for the 5 cross-cutting agentic controls (AC01–AC05). Worker 6 reads this file. Covers:

- AC01: Least-Privilege Tooling
- AC02: Input Guardrails & Context Hygiene
- AC03: Tool I/O Validation
- AC04: Human-in-the-Loop Approvals
- AC05: Observability & Budget Controls

#### references/owasp-llm-checklist.md

Secondary rollup aid used to keep OWASP category alignment and parity-compatible reporting.

#### assets/report-template.md

Markdown template with `{{PLACEHOLDER}}` tokens. The orchestrator fills these in during Phase 3. Includes sections for executive summary, findings by severity, agentic controls summary, SAFE-T coverage, secondary framework rollup, and remediation priority.

### Worker Architecture

#### Why Theme-Based Grouping

Workers are grouped by **security theme**, not by framework. This is a deliberate architectural choice:

```text
  ❌ Framework-based (rejected):         ✅ Theme-based (chosen):
  ┌──────────┐  ┌──────────┐           ┌──────────┐
  │ Worker A │  │ Worker B │           │ Worker 1 │
  │ OWASP    │  │ Agentic  │           │ All      │
  │ LLM01    │  │ ASI01    │           │ injection│
  │          │  │          │           │ concerns │
  │ Reads:   │  │ Reads:   │           │ LLM01 +  │
  │ prompts  │  │ prompts  │  ← same  │ LLM07 +  │
  │ agent cfg│  │ agent cfg│    files! │ ASI01    │
  └──────────┘  └──────────┘           └──────────┘
                                        Reads prompts
                                        & agent cfg ONCE
```

If workers were organized by framework, two workers would still need to read the same prompt and agent files. Theme-based grouping eliminates redundant file I/O and keeps related concerns together.

#### Worker Category Assignments

| Worker | Theme | Primary SAFE-T Techniques | Files Scanned |
|--------|-------|---------------------------|---------------|
| **1** | Injection & Goal Hijack | SAFE-T1102, SAFE-T1110, SAFE-T1401, SAFE-T1402, SAFE-T1001, SAFE-T1008 | LLM API files, prompt files, agent config |
| **2** | Data Disclosure & Supply Chain | SAFE-T1502, SAFE-T1503, SAFE-T1505, SAFE-T1002, SAFE-T1003, SAFE-T1207, SAFE-T1004, SAFE-T1006, SAFE-T1009, SAFE-T1204, SAFE-T2107 | LLM API files, data files, MCP config, agent config |
| **3** | Output, Tool Misuse & Execution | SAFE-T1101, SAFE-T1105, SAFE-T1104, SAFE-T1106, SAFE-T1302, SAFE-T1103, SAFE-T1109, SAFE-T1205, SAFE-T1111, SAFE-T1303, SAFE-T1305 | Output handlers, tool definitions, LLM API files |
| **4** | Identity, Privilege, Memory & RAG | SAFE-T2106, SAFE-T1304, SAFE-T1306, SAFE-T1308, SAFE-T1202, SAFE-T1206, SAFE-T1702 | RAG files, MCP config, agent config |
| **5** | Reliability, Trust & Inter-Agent | SAFE-T2105, SAFE-T1404, SAFE-T2102, SAFE-T1701, SAFE-T1705, SAFE-T1904 | LLM API files, agent config, tool definitions |
| **6** | Agentic Controls & Governance | Uses SAFE-T evidence to score AC01–AC05 | Tool defs, agent config, control files, observability files, budget files |

#### Worker Input Contract

Each worker receives:

1. **File manifest subset** — only files relevant to its categories
2. **Checklist reference** — its section from `references/safe-t-checklist.md` (Workers 1–5), plus secondary mapping context from `references/owasp-llm-checklist.md` when needed; Worker 6 uses `references/agentic-controls.md`
3. **Output format specification** — standardized finding structure

#### Worker Output Contract

Every worker returns findings in a uniform structure:

```markdown
### [SAFE-T####] Technique Name - Brief description
- **File:** path/to/file:line_number
- **Severity:** Critical|High|Medium|Low|Info
- **Secondary:** LLM##, ASI##, AC##
- **Code:**
  ```
  [relevant code snippet, 3-5 lines]
  ```
- **Issue:** What is wrong and why it is dangerous
- **Remediation:** Specific fix with code example if possible
- **Mitigations:** SAFE-M-## (Mitigation Name)
```

If a technique has no findings: `"No issues found for SAFE-T####"`

This uniformity means the orchestrator can mechanically deduplicate, sort, and template the report without needing to understand finding semantics.

### Data Flow

A detailed trace of data through the system:

```text
1. USER invokes /safe-skills:scan
   │
2. COMMAND (scan.md) delegates to SKILL.md
   │
3. ORCHESTRATOR — Phase 1: Discovery
   │  ├─ Glob: package.json, pyproject.toml, go.mod, ...  → project type
   │  ├─ Grep: openai, anthropic, langchain, ...           → LLM SDK files
   │  ├─ Glob: CLAUDE.md, .mcp.json, .cursorrules, ...    → agent/MCP config
   │  ├─ Grep: system prompt, vector DB, embedding, ...   → prompt/RAG files
   │  ├─ Grep: guardrail, approve, audit, rate limit, ... → control points
   │  └─ Builds FILE MANIFEST:
   │     {
   │       llm_api_files:       [src/api/chat.ts, ...]
   │       prompt_files:        [prompts/system.md, ...]
   │       agent_config:        [CLAUDE.md, .cursorrules]
   │       mcp_config:          [.mcp.json]
   │       rag_files:           [src/rag/ingest.ts, ...]
   │       tool_definitions:    [src/tools/*.ts]
   │       data_files:          [data/training.jsonl]
   │       output_handlers:     [src/api/response.ts, ...]
   │       control_files:       [src/guardrails.ts, ...]
   │       observability_files: [src/logging.ts, ...]
   │       budget_files:        [src/ratelimit.ts, ...]
   │     }
   │
4. ORCHESTRATOR — Phase 2: Dispatch
   │  Spawns 6 workers in a SINGLE parallel call.
   │  Each receives: manifest subset + checklist section reference.
   │
   ├─ WORKER 1 reads safe-t-checklist.md §Worker1
   │  ├─ Read: llm_api_files, prompt_files, agent_config
   │  ├─ Grep: template literals, f-strings, role separation, ...
   │  └─ Returns: [{SAFE-T1102, Critical, ...}, {SAFE-T1110, High, ...}]
   │
   ├─ WORKER 2 reads safe-t-checklist.md §Worker2
   │  ├─ Read: llm_api_files, data_files, mcp_config, agent_config
   │  ├─ Grep: process.env, credentials, model URLs, lockfiles, ...
   │  └─ Returns: [{SAFE-T1502, Critical, ...}, {SAFE-T1004, High, ...}]
   │
   ├─ WORKER 3 reads safe-t-checklist.md §Worker3
   │  ├─ Read: output_handlers, tool_definitions, llm_api_files
   │  ├─ Grep: eval(, exec(, innerHTML, subprocess, ...
   │  └─ Returns: [{SAFE-T1101, Critical, ...}, {SAFE-T1302, High, ...}]
   │
   ├─ WORKER 4 reads safe-t-checklist.md §Worker4
   │  ├─ Read: rag_files, mcp_config, agent_config
   │  ├─ Grep: vector DB connections, token expiry, memory writes, ...
   │  └─ Returns: [{SAFE-T2106, High, ...}, {SAFE-T1308, Medium, ...}]
   │
   ├─ WORKER 5 reads safe-t-checklist.md §Worker5
   │  ├─ Read: llm_api_files, agent_config, tool_definitions
   │  ├─ Grep: max_tokens, rate limit, circuit breaker, retry, ...
   │  └─ Returns: [{SAFE-T2102, Medium, ...}, {SAFE-T1705, Medium, ...}]
   │
   └─ WORKER 6 reads agentic-controls.md
      ├─ Read: tool_definitions, agent_config, control_files,
      │        observability_files, budget_files
      ├─ Grep: allowlist, approve, audit, rate limit, timeout, ...
      └─ Returns: [{AC01, High, ...}, {AC05, Medium, ...}]
   │
5. ORCHESTRATOR — Phase 3: Report Generation
   │  ├─ Collects all findings from 6 workers
   │  ├─ Deduplicates: same file:line flagged by multiple workers
   │  │   → keeps higher severity, merges secondary mappings and mitigations
   │  ├─ Sorts: Critical > High > Medium > Low > Info
   │  ├─ Reads: assets/report-template.md
   │  ├─ Fills: {{PLACEHOLDERS}} with findings, counts, coverage
   │  ├─ Writes: docs/security/llm-vulnerability-report.md
   │  └─ Displays: executive summary table to user
   │
6. USER sees:
   ## LLM Vulnerability Scan Complete
   | Severity | Count |
   |----------|-------|
   | Critical | 2     |
   | High     | 5     |
   | Medium   | 3     |
   | Low      | 1     |
   | Info     | 0     |
   Overall Risk: Critical
   Primary Taxonomy: SAFE-T
   Scan Type: Full
   Scan Scope: repo-scope
   Report saved to: docs/security/llm-vulnerability-report.md
```

### Key Design Patterns

#### 1. Progressive Disclosure (Context Window Management)

LLMs have finite context windows. Loading 400+ lines of detection patterns into every conversation would waste tokens. The solution is a **two-tier information architecture**:

```text
Tier 1: SKILL.md (~250 lines)
  - Always loaded when skill activates
  - Contains pipeline logic, worker dispatch, report generation
  - No detection patterns — just structure

Tier 2: references/ (loaded on demand)
  - safe-t-checklist.md — primary technique checklist, loaded by workers
  - owasp-llm-checklist.md (~400 lines) — secondary OWASP rollup mapping
  - agentic-controls.md (~90 lines) — loaded by Worker 6 for AC01–AC05 scoring
  - Each worker loads ONLY its section, not the full file
```

This means the orchestrator context stays lean. Workers load heavy references only when they execute. The Agent Skills specification recommends keeping `SKILL.md` under 500 lines for this reason.

#### 2. File Manifest as a Contract

Phase 1 produces a categorized file manifest that acts as a **contract between orchestrator and workers**:

```text
llm_api_files:       Files that import/call LLM APIs
prompt_files:        Files containing prompt templates or system prompts
agent_config:        Agent configuration files (CLAUDE.md, .cursorrules, etc.)
mcp_config:          MCP server/tool configurations
rag_files:           RAG pipeline, vector DB, embedding code
tool_definitions:    MCP tool schemas and handlers
data_files:          Training data, fine-tuning datasets (JSONL, CSV)
output_handlers:     Files that process/render LLM responses
control_files:       Guardrail, policy, approval, and permissions config
observability_files: Logging, tracing, monitoring around agent/tool actions
budget_files:        Rate limiting, token/cost caps, retries, circuit breakers
```

Each worker receives **only its relevant subset**. This prevents workers from scanning irrelevant files and keeps their context focused on what matters for their security theme.

#### 3. Standardized Finding Format

Every worker outputs findings in an identical structure. This enables the orchestrator to:

- **Deduplicate** without understanding semantics (match on `file:line`)
- **Sort** mechanically (severity enum ordering)
- **Template** by string replacement (fill `{{PLACEHOLDERS}}`)
- **Count** by severity for the executive summary

The format was designed to be both machine-processable and human-readable.

#### 4. Zero Runtime Dependencies

The entire scanner uses the host agent's built-in tools:

| Operation | Tool Used | Why Not External |
|-----------|-----------|-----------------|
| Read files | `Read` tool | No `cat`, no file system library |
| Search code | `Grep` tool | No `ripgrep` binary needed |
| Find files | `Glob` tool | No `find` command needed |
| Parallel workers | `Task` tool | No process spawning, no Docker |
| Output | `Write` tool | No template engine library |

This means: no `npm install`, no `pip install`, no Docker, no external API calls. The LLM itself is the scanner engine. The skill is pure markdown that instructs the LLM how to analyze code.

#### 5. LLM-as-Scanner (Semantic Analysis)

This is a fundamentally different approach from traditional SAST tools:

| Aspect | Traditional SAST (Semgrep, SonarQube) | safe-skills |
|--------|---------------------------------------|-------------|
| **Analysis method** | AST parsing + pattern matching | LLM semantic understanding |
| **Pattern definition** | YAML/JSON rules with syntax patterns | Natural language descriptions |
| **Data flow tracking** | Taint analysis (deterministic) | Contextual reasoning (probabilistic) |
| **Strengths** | Deterministic, fast, zero false negatives for known patterns | Can catch semantic issues no regex would find (e.g., "this prompt template builds system prompts from user-controlled DB fields") |
| **Weaknesses** | Can't reason about intent or context | Non-deterministic; depends on LLM capability; may hallucinate findings |
| **Best for** | Known vulnerability patterns at scale | Novel LLM-specific vulnerabilities where patterns don't exist yet |

The tradeoff is intentional: LLM-specific vulnerabilities are too new and too varied for static pattern databases. The LLM's ability to reason about code semantics — "this function passes user input through three transformations, then uses it as a system prompt" — catches things that no regex could.

### Design Decisions

Summary of key architectural decisions and alternatives considered:

| Decision | Chosen | Alternative | Why This Won |
|----------|--------|-------------|-------------|
| **Format** | Claude Code plugin | Standalone CLI tool | Runs inside the agent that writes the code — zero friction |
| **MCP server** | None | MCP server wrapping scanner | Local file analysis only; MCP adds infra with no benefit |
| **Worker count** | 6 themed workers | 7 kill-chain workers (Option B) | 20 categories more manageable than 81 TTPs |
| **SAFE-MCP role** | Primary taxonomy (`SAFE-T####`) with OWASP/AC secondary rollups | OWASP-primary reference layer | Aligns reporting to SAFE-MCP while preserving compliance-friendly rollups |
| **Skill format** | Agent Skills open standard | Claude-only SKILL.md | One file works across Claude Code, Cursor, Codex |
| **Installation** | Copy installer (`--symlink` optional) | npm/pip package | No runtime deps; copy mode is safer and reproducible |
| **Reference files** | Lazy-loaded by workers | Embedded in SKILL.md | Respects context window limits (progressive disclosure) |
| **Worker grouping** | By security theme | By framework | Eliminates redundant file reads across related categories |
| **Report format** | Markdown with template | JSON or HTML | Readable in any editor; diffable in git; no rendering deps |

For the full decision rationale, see the design decision table above and the inline comments throughout this document.

### Severity Classification

| Severity | Criteria | Examples |
|----------|----------|---------|
| **Critical** | Direct code execution, prompt injection with no sanitization, exposed secrets in prompts, RCE vectors | `eval(llmOutput)`, API key in system prompt, unsandboxed code execution |
| **High** | Excessive permissions, missing output validation before DB/shell, unverified supply chain, sandbox escape | Overly broad tool permissions, LLM output to SQL without parameterization |
| **Medium** | Missing rate limits, broad tool access, no access partitioning, missing integrity checks | No `max_tokens`, shared vector collections without tenant filtering |
| **Low** | Missing monitoring, no source attribution, incomplete error handling, no behavioral tracking | No audit logging, missing decision transparency |
| **Info** | Best practice recommendations, defense-in-depth suggestions | Adding behavioral monitoring, implementing kill switches |

### Quick Scan Mode

When invoked with "quick" (`/safe-skills:scan quick`), the scanner skips Medium, Low, and Info patterns. Only Critical and High severity checks run. This is designed for rapid feedback during active development — catch the dangerous issues fast, save the comprehensive audit for pre-release.

---

## References

- [OWASP LLM Top 10 (2025)](https://genai.owasp.org/resource/owasp-top-10-for-llm-applications-2025/)
- [OWASP Agentic Top 10 (2026)](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/)
- [SAFE-MCP Framework](https://github.com/SAFE-MCP/safe-mcp)
- [Agent Skills Specification](https://agentskills.io/specification)
- [Vercel Claude Code Plugin](https://github.com/vercel/vercel-deploy-claude-code-plugin) (distribution model reference)
