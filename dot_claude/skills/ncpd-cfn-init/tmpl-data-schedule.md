# tmpl-data-schedule

EventBridge Scheduler → SQS → Lambda architecture for scheduled data processing.

## Architecture

```txt
EventBridge Scheduler → SQS Queue → Lambda Function
                            ↓
                       Dead Letter Queue → CloudWatch Alarm
```

## Components

### CloudFormation Resources

- **AWS::Serverless::Function** - Lambda function with SQS event source
- **AWS::Scheduler::Schedule** - EventBridge Scheduler with cron expression
- **AWS::SQS::Queue** - Main queue with DLQ redrive policy
- **AWS::SQS::Queue** - Dead letter queue for failed messages
- **AWS::CloudWatch::Alarm** - Alarm on DLQ message count
- **AWS::Logs::LogGroup** - CloudWatch log group with retention
- **AWS::Logs::SubscriptionFilter** - Log filter for alerts

### Lambda Configuration

- Runtime: Python 3.13 (ARM64)
- Timeout: 300 seconds
- Memory: 1024 MB
- Layers: wni, common, Powertools, AWS SDK Pandas

### Key Features

- Cron-based scheduling with Asia/Tokyo timezone
- Batch processing with `ReportBatchItemFailures`
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
│   │   ├── values/
│   │   │   └── __init__.py
│   │   ├── __init__.py
│   │   ├── __main__.py
│   │   └── lambda_function.py
│   └── tests/
│       └── __init__.py
├── deploy_pipeline.sh
├── sync.sh
├── template.yaml
└── upload_to_pipeline.sh
```

## Usage

```bash
~/.claude/skills/ncpd-cfn-init/scripts/scaffold.sh tmpl-data-schedule <destination_path> <directory_name>
```

## Minimum Customization Points

After copying, modify:

1. **template.yaml**

   - `Schedule.ScheduleExpression` - Set cron expression (e.g., `cron(0 9 * * ? *)`)

2. **src/app/lambda_function.py**

   - Implement `record_handler` function body (receives `time: Timestamp`, `detail: dict`)

3. **src/app/values/\_\_init\_\_.py**
   - Add constants and environment variables
