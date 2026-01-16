---
name: ncpd-cfn-init
description: AWS CloudFormation templates for Lambda projects. Use when scaffolding new CloudFormation stacks.
---

# NCPD CloudFormation Templates

This skill helps you scaffold AWS CloudFormation templates with Lambda functions.

## Available Templates

| Template           | Description                                    | Details                                          |
| ------------------ | ---------------------------------------------- | ------------------------------------------------ |
| tmpl-data-schedule | Scheduler → SQS → Lambda scheduled task        | [tmpl-data-schedule.md](./tmpl-data-schedule.md) |
| tmpl-data-stock    | SNS → SQS → Lambda Stock on S3 data processing | [tmpl-data-stock.md](./tmpl-data-stock.md)       |

## Usage

1. Read the template details via the links above
2. Run the shell script in `scripts/` to copy the template:

```bash
~/.claude/skills/ncpd-cfn-init/scripts/scaffold.sh <template_name> <destination_path> <directory_name>
```
