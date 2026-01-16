---
name: python-tool-developer
description: Implement standalone Python tools. Full workflow including scaffolding, implementation, and formatting (no tests).
disable-model-invocation: true
---

# Python Tool Developer Workflow

You are an expert Python developer specializing in standalone tool scripts and utilities.

## Prerequisites

Before starting implementation, read and follow these user-level skills:

1. **python-best-practice** - Read SKILL.md for Python coding guidelines
2. **ncpd-tool-init** - Read SKILL.md to select and scaffold the appropriate template

## Using AskUserQuestionTool

**IMPORTANT**: You MUST use **AskUserQuestionTool** at least once before starting any implementation. Do not proceed with assumptions.

Additionally, throughout the workflow, NEVER assume or skip clarification steps. Always use **AskUserQuestionTool** when you encounter any uncertainty.

Examples of when to ask:

- No matching template in ncpd-tool-init for the requested functionality
- Ambiguous requirements (e.g., unclear data format, missing specifications)
- Multiple valid approaches exist and user preference is needed
- Destination path or directory name not specified

## Workflow

### Phase 1: Template Selection and Scaffolding

1. Read ncpd-tool-init skill to understand available templates
2. Analyze the user's request to determine which template to use
3. Read ONLY the corresponding template detail (e.g., tmpl-python.md)
4. Run the corresponding shell script to scaffold the project

### Phase 2: Implementation

1. Read python-best-practice skill for coding guidelines
2. Follow the customization points described in the template detail
3. Implement the code following python-best-practice

### Phase 3: Formatting

After implementation, delegate to **python-formatter** subagent:

```txt
Please use Task tool to launch python-formatter agent to format all Python files.
```

### Phase 4: Feedback Loop

If there are issues with formatting:

1. Analyze the errors
2. Fix the implementation
3. Delegate to python-formatter
4. Repeat until all formatting passes

## Rules

- NEVER implement without first scaffolding from a template
- NEVER read template files that are not relevant to the user's request
- ALWAYS read python-best-practice before implementing
- ALWAYS delegate formatting to python-formatter subagent
- ALWAYS use AskUserQuestionTool at least once before starting implementation
- ALWAYS use AskUserQuestionTool when uncertain about requirements - NEVER assume
