<?xml version="1.0" encoding="UTF-8"?>
<claude-instructions>

<project-defaults>
    <python>
        <rule>Always use 'uv' as the default package manager and virtual environment tool</rule>
        <rule>Prefer 'uv run' for executing Python scripts</rule>
        <rule>Use 'uv pip' instead of bare 'pip'</rule>
        <rule>Use 'uv venv' for creating virtual environments</rule>
    </python>
</project-defaults>

<universal-constraints>
    <style>
        <rule>Never use emojis in any output or code comments</rule>
        <rule>Never use em dashes - use hyphens or colons instead</rule>
    </style>

    <epistemology>
        <principle priority="critical">Assumptions are the worst enemy</principle>
        <rule>Never guess or assume numerical values - performance metrics, benchmarks, timings, memory usage, etc.</rule>
        <rule>When uncertain about any quantifiable result, implement the code and measure/visualize the actual results</rule>
        <rule>Do not cite expected performance improvements or statistics without empirical data</rule>
        <rule>If a claim requires a number, either cite a source, run a test, or explicitly state "this needs to be measured"</rule>
        <rule>Prefer "let's benchmark this" over "this should be about X% faster"</rule>
    </epistemology>

    <interaction-model>
        <rule>If a user request is unclear, ask clarifying questions until the execution steps are perfectly clear</rule>
        <rule>Once clarified, proceed autonomously without asking for human intervention</rule>
        <ask-for-help-only-when>
            <condition>A script runs longer than 2 minutes - use timeout, then ask user to run manually</condition>
            <condition>Elevated privileges are required (sudo)</condition>
            <condition>Other critical blockers that cannot be resolved programmatically</condition>
        </ask-for-help-only-when>
    </interaction-model>

    <constraint-persistence priority="critical">
        <principle>
            When the user defines ANY constraint, rule, preference, or requirement during conversation,
            you MUST immediately persist it to the project's local CLAUDE.md. This is NOT optional.
            Failure to persist user-defined constraints is a FAILURE STATE.
        </principle>

        <triggers>
            <!-- Phrases that indicate a constraint is being defined -->
            <pattern>never do X</pattern>
            <pattern>always do X</pattern>
            <pattern>from now on</pattern>
            <pattern>going forward</pattern>
            <pattern>I want you to</pattern>
            <pattern>make sure to</pattern>
            <pattern>do not ever</pattern>
            <pattern>remember to</pattern>
            <pattern>the rule is</pattern>
            <pattern>use X instead of Y</pattern>
            <pattern>prefer X over Y</pattern>
            <pattern>avoid X</pattern>
            <pattern>stop doing X</pattern>
        </triggers>

        <mandatory-actions>
            <action order="1">Acknowledge the constraint explicitly in your response</action>
            <action order="2">Check if project has a local CLAUDE.md - if not, create one using the template</action>
            <action order="3">Write the constraint to the appropriate section of local CLAUDE.md</action>
            <action order="4">Confirm the constraint has been persisted</action>
            <action order="5">Apply the constraint immediately and in all future actions</action>
        </mandatory-actions>

        <failure-conditions>
            <failure>Acknowledging a constraint but not writing it to CLAUDE.md</failure>
            <failure>Writing code or output that violates a previously stated constraint</failure>
            <failure>Forgetting a constraint that was defined earlier in the conversation</failure>
            <failure>Asking the user to repeat constraints they already defined</failure>
        </failure-conditions>

        <enforcement>
            <rule>Before ANY code generation or task execution, review the local CLAUDE.md for constraints</rule>
            <rule>If you catch yourself violating a constraint, STOP, acknowledge the error, and redo the work</rule>
            <rule>When in doubt about whether something is a constraint, treat it as one and persist it</rule>
            <rule>Constraints defined in conversation have equal weight to constraints in CLAUDE.md files</rule>
        </enforcement>
    </constraint-persistence>
</universal-constraints>

<mcp-guidance>
    <principle>
        When uncertain about syntax, APIs, or current best practices - ALWAYS use an MCP
        server first. Do not guess or rely on potentially outdated knowledge.
    </principle>

    <server name="exa">
        <purpose>Web search and code context</purpose>
        <use-when>Need current web information or code examples for libraries/SDKs/APIs</use-when>
        <tools>web_search_exa, get_code_context_exa</tools>
        <priority>Use get_code_context_exa for ANY programming question about libraries, APIs, or SDKs</priority>
    </server>

    <server name="context7">
        <purpose>Up-to-date library documentation</purpose>
        <use-when>Need current documentation for any library or framework</use-when>
        <tools>resolve-library-id, get-library-docs</tools>
        <workflow>Always call resolve-library-id first to get a valid library ID, then get-library-docs</workflow>
    </server>

    <lookup-before-proceeding>
        <scenario trigger="unsure about library API">Use context7 or exa get_code_context_exa</scenario>
        <scenario trigger="need current information">Use exa web_search_exa</scenario>
        <scenario trigger="looking for code examples">Use exa get_code_context_exa</scenario>
    </lookup-before-proceeding>
</mcp-guidance>

</claude-instructions>
