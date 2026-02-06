---
description: Deterministically scan LLM application code for SAFE-MCP SAFE-T techniques (primary), with OWASP LLM/Agentic and agentic controls as secondary mappings
---

# LLM Vulnerability Scan

Run a security audit using the `llm-vulnerability-scan` skill.

1. Select scan mode deterministically:
   - `quick` argument or explicit "critical/high only" intent -> Quick
   - Otherwise -> Full
2. Select scope deterministically:
   - Default: repo scope (tracked files when available)
   - Include local/untracked machine configs only if arguments include `include-local-config`
3. Run the skill and generate SAFE-T keyed findings.
4. Save report to `docs/security/llm-vulnerability-report.md`.
5. Display an executive summary with Severity, Overall Risk, Primary Taxonomy, Scan Type, and Scan Scope.
