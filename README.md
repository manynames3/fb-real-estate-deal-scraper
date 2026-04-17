# AWS FB Deal Finder

An event-driven AWS pipeline that monitors Facebook real estate groups, detects motivated-seller signals, deduplicates posts, and sends real-time alerts.

This project is designed as a lightweight serverless workflow for lead discovery. It uses AWS Lambda, EventBridge, DynamoDB, and SNS to poll an external data source on a schedule, score new posts against acquisition keywords, and notify the operator when a potentially valuable lead appears.

## Why this project exists

Real estate investor communities generate a steady stream of posts, but the useful ones are buried in noise and disappear quickly. This project automates the first-pass screening process so new opportunities can be surfaced quickly without manually checking multiple groups throughout the day.

## What it does

- Fetches recent posts from configured Facebook groups on a recurring schedule
- Scans post text for motivated-seller and distress keywords
- Deduplicates previously seen posts using DynamoDB
- Sends real-time alerts through Amazon SNS
- Automatically expires old post records using DynamoDB TTL
- Keeps monthly operating cost low by relying on serverless components

## Architecture

```text
ScrapeCreators API
        |
        v
EventBridge schedule (every 4 hours)
        |
        v
AWS Lambda (Python)
  - fetch posts for each group
  - score posts by keyword match
  - check DynamoDB for duplicates
  - persist unseen posts
  - publish alert for matches
        |
        +--> DynamoDB (seen posts + TTL)
        |
        +--> SNS (email / SMS alerts)
```

## AWS services used

### AWS Lambda
Runs the scheduled Python job that handles ingestion, filtering, deduplication, and alerting.

### Amazon EventBridge
Triggers the Lambda function every 4 hours.

### Amazon DynamoDB
Stores post identifiers so the same post is not alerted twice. TTL is used to remove old records automatically.

### Amazon SNS
Sends notifications by email and SMS when a new post matches one or more deal keywords.

## Processing flow

1. EventBridge invokes the Lambda function on a fixed schedule.
2. Lambda requests recent posts from the configured source for each group URL.
3. Each post is normalized into a deterministic post ID.
4. The post text is matched against a keyword library.
5. If the post has no relevant signals, it is ignored.
6. If the post was already processed, it is skipped.
7. If the post is new and relevant, it is written to DynamoDB and an alert is published through SNS.

## Keyword strategy

The scoring model is intentionally simple and transparent. Instead of using a black-box classifier, the project starts with a curated keyword set covering:

- motivated seller language
- distress indicators
- property-condition signals
- wholesale and off-market terms
- target-market geography

This makes it easy to tune the system for new markets or acquisition strategies.

## Deduplication design

To avoid duplicate alerts, each post is assigned a stable ID derived from the best available identifier from the source payload, such as:

- post ID
- post URL
- truncated post text fallback

That value is hashed and stored in DynamoDB. If the hash already exists, the alert is skipped.

## Example alert payload

```text
DEAL ALERT

BY: Jane Seller
DATE: 2026-04-17

POST:
Inherited property in Gwinnett County. Needs work and looking for a cash buyer.

KEYWORDS:
inherited, needs work, cash buyer, gwinnett

LINK:
https://example.com/post/123
```

## Cost profile

The system is intentionally low-cost.

- Lambda: typically covered by free tier at this usage level
- DynamoDB: minimal storage and read/write usage
- EventBridge: negligible scheduler cost at low volume
- SNS Email: typically free
- SNS SMS: variable, depending on alert volume
- External scraping API: primary paid component

This makes the design practical for solo operators, small internal tools, or low-volume lead pipelines.

## Security notes

This repository does **not** store production secrets.

### Keep out of source control

- API keys
- AWS account-specific ARNs
- real phone numbers
- real email endpoints
- private source URLs if they expose business strategy

### Recommended secret handling

- Lambda environment variables for basic deployments
- AWS Secrets Manager or Parameter Store for stronger production hygiene
- least-privilege IAM permissions instead of broad admin policies

## Repository contents

```text
.
├── README.md
├── src/
│   └── lambda_function.py
├── tests/
├── examples/
│   ├── sample_post.json
│   ├── sample_alert.txt
│   └── sample_dynamodb_item.json
├── docs/
│   └── architecture.md
├── infra/
│   └── terraform/ or cdk/
├── .env.example
└── SECURITY.md
```

## Local development

Use placeholder values locally and never commit real credentials.

Example environment variables:

```bash
SCRAPECREATORS_API_KEY=your_api_key_here
FB_GROUP_URLS=https://www.facebook.com/groups/example1,https://www.facebook.com/groups/example2
SNS_TOPIC_ARN=arn:aws:sns:us-east-1:123456789012:deal-alerts
DYNAMODB_TABLE=fb-deal-posts
AWS_REGION=us-east-1
```

## Production improvements

The current design is a solid MVP. Strong next steps include:

- Infrastructure as Code with Terraform or AWS CDK
- unit tests for keyword scoring and dedup logic
- structured logging and metrics
- dead-letter queue handling
- alert throttling or daily digest mode
- web dashboard for reviewing archived leads
- AI-based lead scoring for higher precision

## Resume / portfolio value

This project demonstrates:

- serverless architecture on AWS
- event-driven design
- external API integration
- deduplication and idempotency patterns
- NoSQL persistence with TTL lifecycle management
- notification workflows
- cost-aware cloud design
- security-conscious handling of configuration and secrets

## Notes

This repository is intended to show the engineering design and implementation pattern behind the system. Any deployment-specific values should be redacted or replaced with placeholders before publication.
