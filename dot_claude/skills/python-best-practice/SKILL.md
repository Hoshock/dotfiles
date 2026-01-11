---
name: python-best-practice
description: Python coding best practices for AWS Lambda projects. Use when writing, reviewing, or modifying Python code.
---

# Python Best Practices

Follow PEP8 with the following additions. Linting and formatting are handled by ruff.

## Common

- Define functions in logical order for readability
- Keep comments/docstrings up to date, or remove them
- NEVER overwrite function arguments (avoid side effects)
- Remove dead code

## Built-in Libraries

### round

NEVER use `round` built-in (banker's rounding). Use:

```python
def round(value: float, scale: int) -> float:  # noqa: A001
    data = value * (10**scale) + 0.5 if value >= 0 else value * (10**scale) - 0.4
    return int(data) / (10**scale)
```

### datetime

- NEVER use `datetime` module. Use `pd.Timestamp` or `pd.Timedelta`
- NEVER use `datetime.now`. Use Lambda events for idempotency

### io

- Use `io.BytesIO` for small files from S3

### logging

- NEVER use `logging` module. Use `aws_lambda_powertools.logging`

### os

- NEVER use `os.environ`. Use `python-decouple` or `pydantic`

### re

- Avoid regex unless necessary. Prefer string methods

### tempfile

- Use `tempfile.NamedTemporaryFile` or `NamedTemporaryDirectory` for large S3 files

## Third-Party Libraries

### boto3

NEVER use `boto3` directly. Prefer awswrangler or AWS Lambda Powertools. If needed, use `wni.aws`.

- Pass URI as list: `df = s3.read_csv([uri])`
- Prefer `boto3.resource` over `boto3.client`
- NEVER define boto3 resources at global scope (breaks moto testing)
- NEVER define boto3 resources within functions (expensive initialization)

### Powertools for AWS Lambda

- Use `pydantic` for API validation

## Logging

- Use `aws_lambda_powertools.logging.Logger`
- NEVER log large data structures
- NEVER log sensitive information
- No need for `logger.exception` or `logger.error`. Just raise exceptions (`wni.handler` handles logging)

## Error Handling

- NEVER use try-catch unless you can handle the exception properly
- NEVER catch broad exceptions like `Exception`
