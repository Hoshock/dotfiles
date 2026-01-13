# tmpl-data-stock

SNS → SQS → Lambda architecture for Stock on S3 data processing.

## Architecture

```txt
SNS Topic → SQS Queue → Lambda Function
                ↓
           Dead Letter Queue → CloudWatch Alarm
```

## Components

### CloudFormation Resources

- **AWS::Serverless::Function** - Lambda function with SQS event source
- **AWS::SQS::Queue** - Main queue with DLQ redrive policy
- **AWS::SQS::Queue** - Dead letter queue for failed messages
- **AWS::CloudWatch::Alarm** - Alarm on DLQ message count
- **AWS::SNS::Subscription** - SNS to SQS subscription with filter policy
- **AWS::Logs::LogGroup** - CloudWatch log group with retention
- **AWS::Logs::SubscriptionFilter** - Log filter for alerts

### Lambda Configuration

- Runtime: Python 3.13 (ARM64)
- Timeout: 300 seconds
- Memory: 1024 MB
- Layers: wni, common, Powertools, AWS SDK Pandas

### Key Features

- Batch processing with `ReportBatchItemFailures`
- SNS filter policy support (`time_diff <= 3600`)
- DLQ with 3 retry attempts
- Log subscription for WARNING/ERROR alerts

## File Structure

```txt
<directory_name>/
├── cfn_params/
│   ├── param_common.json
│   ├── param_dev.json
│   ├── param_prd.json
│   └── param_stg.json
├── src/
│   ├── app/
│   │   ├── __init__.py
│   │   ├── __main__.py
│   │   ├── lambda_function.py
│   │   └── values/
│   │       └── __init__.py
│   └── tests/
│       └── __init__.py
├── template.yaml
├── deploy_pipeline.sh
├── sync.sh
└── upload_to_pipeline.sh
```

## Usage

```bash
~/.claude/skills/ncpd-template-init/scripts/tmpl-data-stock.sh <destination_path> <directory_name>
```

## Customization Points

After copying, modify:

1. **template.yaml**

   - `Mappings.Const.Topic.Arn` - Set correct SNS topic ARN

2. **src/app/lambda_function.py**

   - Implement `record_handler` function body

3. **src/app/values/\_\_init\_\_.py**
   - Add constants and environment variables
