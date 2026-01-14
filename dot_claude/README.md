# Claude Code Usage Guide

This document explains how to set up and use the development environment with Claude Code.

## Prerequisites

### 1. Clone Repositories

Clone the following repositories under `~/Projects`:

```bash
cd ~/Projects

git clone <NCPD-Template-Child-repository-url> NCPD-Template-Child
git clone <Hoshock-CFn-Suite-repository-url> Hoshock-CFn-Suite
```

### 2. Install Python Tools

Install `ruff` (formatter/linter) and `ty` (typo checker):

```bash
brew install ruff ty
```

### 3. Set Up Symbolic Links

To reference templates from `NCPD-Template-Child` in `Hoshock-CFn-Suite`, run the following commands to set up symbolic links:

```bash
cd ~/Projects/Hoshock-CFn-Suite
mkdir -p cfn/tmpl

cd cfn/tmpl
for item in ../../../NCPD-Template-Child/cfn/tmpl/*; do
  ln -s "$item" "$(basename "$item")"
done
```

After running these commands, the `cfn/tmpl/` directory will contain:

- Project-specific templates as actual directories
- Symbolic links to shared templates from `NCPD-Template-Child`

## Usage

### Launching Claude Code

1. Open your target project in VS Code
2. Start Claude Code

### Creating a New CloudFormation Stack

Use the `/python-developer` command followed by your requirements:

```txt
/python-developer Stock on S3のTagID 1234というGRIBデータを受信してparquetに変換するCFnを実装してください
```

This command will:

1. Select the appropriate template from `ncpd-template-init`
2. Scaffold the project structure
3. Implement the Lambda function following `python-best-practice`
4. Format the code with `python-formatter`
5. Write tests with `python-test-writer`
6. Format the tests with `python-formatter`
7. Run feedback loop if tests fail (fix → format → update tests → format tests)
