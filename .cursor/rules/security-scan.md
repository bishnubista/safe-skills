# Cursor Security Scan Rule

Use this rule when the user asks to scan, audit, or review a codebase for LLM, agentic, prompt-injection, or MCP security issues.

Cursor is rule-driven (no first-class `SKILL.md` runtime contract), so this file is the Cursor-first adapter.

## Invocation Guidance

1. Default to **Full** scan unless the user explicitly asks for `quick` or critical/high-only scan.
2. Default to **repo scope** (tracked files when available). Include local/untracked machine config only when explicitly requested.
3. Use SAFE-T techniques as the primary taxonomy source.
4. Use OWASP LLM/Agentic and Agentic Controls as secondary mappings.
5. Preserve SAFE-T as the primary finding taxonomy, and include (`LLM01-10`, `ASI01-10`, `AC01-05`) as secondary mappings.
6. Always write `docs/security/llm-vulnerability-report.md` and return an executive summary with Severity, Overall Risk, Scan Type, and Scan Scope.

## Non-Goals

- Do not infer scan mode/scope from prior reports.
- Do not redefine category mappings outside the shared checklist references.
