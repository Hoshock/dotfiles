# tmpl-python

StateMachine batch executor with uv/ruff for standalone Python tool projects.

## Architecture

```txt
main.sh → src/main.py → AWS Step Functions StateMachine
                             ↓
                        Bulk execution with concurrency control
```

## Components

### Project Configuration

- **uv** - Python package manager with lock file
- **ruff** - Fast Python linter and formatter
- **VSCode workspace** - Pre-configured development environment

### Key Features

- Batch execution with configurable concurrency limit
- Environment-specific parameter files (dev/stg/prd)
- VSCode debugging support
- Clean dependency management with uv.lock

## File Structure

```txt
<directory_name>/
├── cfn_params/
│   ├── param_dev.json      # Dev environment parameters
│   ├── param_stg.json      # Stg environment parameters
│   └── param_prd.json      # Prd environment parameters
├── src/
│   └── main.py             # Main script
├── develop.code-workspace  # VSCode workspace configuration
├── main.sh                 # Entry point
├── pyproject.toml          # Python dependencies
└── uv.lock                 # UV lock file
```

## Prerequisites

```shell
brew install uv
uv sync
```

## Usage

```bash
~/.claude/skills/ncpd-tool-init/scripts/scaffold.sh tmpl-python <destination_path> <directory_name>
```

### Running the Tool

1. Open `develop.code-workspace` in VSCode
2. Update `infra` folder path in `develop.code-workspace` to match your environment
3. Run from VSCode integrated terminal:

```shell
./main.sh <dev|stg|prd>
```

### Debugging (Optional)

Update `args` in `develop.code-workspace` launch configuration:

- `args[0]`: StateMachine ARN
- `args[1]`: AWS profile name

## Minimum Customization Points

After copying, modify:

1. **cfn_params/\*.json**

   - `StateMachineArn` - Target StateMachine ARN

2. **src/main.py**

   - `CONCURRENT_LIMIT` - Number of executions per batch (default: 10)
   - `SLEEP_SECONDS` - Sleep duration between batches (default: 1.0)
   - `get_target_items()` - Returns list of items to process
   - `create_payload()` - Generates payload for StateMachine
