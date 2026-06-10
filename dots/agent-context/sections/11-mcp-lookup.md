---
name: mcp-lookup
disclosure: progressive
description: "Which MCP servers to use for library docs, code examples, and current web information. Use when uncertain about a library API, SDK, framework syntax, or any current best practice instead of guessing."
---
## MCP lookup

When uncertain about syntax, APIs, or current best practices, always use an
MCP server first. Do not guess or rely on potentially outdated knowledge.

### exa (web search and code context)

- Tools: `web_search_exa`, `get_code_context_exa`.
- Use `get_code_context_exa` for ANY programming question about libraries,
  APIs, or SDKs.
- Use `web_search_exa` when current web information is needed.

### context7 (library documentation)

- Tools: `resolve-library-id`, `get-library-docs`.
- Always call `resolve-library-id` first to get a valid library ID, then
  `get-library-docs`.

### Lookup before proceeding

- Unsure about a library API: context7 or exa `get_code_context_exa`.
- Need current information: exa `web_search_exa`.
- Looking for code examples: exa `get_code_context_exa`.
