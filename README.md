# FB Deal Finder — Automated Real Estate Deal Scout
### Clearpath Property Group | Built on AWS

An automated AWS pipeline that monitors public Facebook real estate groups for motivated seller posts, filters them using keyword scoring, deduplicates results, and delivers email alerts in real time.

Built as a practical lead generation tool for real estate wholesaling and as a hands-on AWS portfolio project covering Lambda, DynamoDB, SNS, EventBridge, IAM, and CloudWatch.

![Lambda test success](docs/screenshots/21-lambda-test-success.png)

## What It Does

- Calls the ScrapeCreators API on a schedule to pull new posts from 5 public Atlanta-area real estate Facebook groups
- Scores each post against a curated list of motivated seller keywords like `motivated`, `as-is`, `inherited`, `probate`, `vacant`, and `off market`
- Filters out retail and realtor listings using a negative keyword list like `just listed`, `realtor`, `keller williams`, and `mls#`
- Checks DynamoDB to skip posts already seen so you do not get duplicate alerts
- Sends an email alert via SNS with the post text, author, keywords matched, and a direct link to the Facebook post
- Automatically deletes seen posts from DynamoDB after 30 days via TTL

## Architecture

```text
ScrapeCreators API
(fetches 3 posts per FB group per call)
        ↓
EventBridge Scheduler
(triggers Lambda every 3 days at 11 PM ET)
        ↓
Lambda Function (Python 3.12)
  → calls ScrapeCreators for each group
  → scores posts against DEAL_KEYWORDS
  → filters against NEGATIVE_KEYWORDS
  → checks DynamoDB: already seen? skip
  → saves new matching posts to DynamoDB
  → publishes SNS alert for each match
        ↓
SNS Topic → Email alert to you
        ↓
DynamoDB
(stores seen post IDs with 30-day TTL)
        ↓
CloudWatch Logs
(full execution logs per run)
```

## AWS Services Used

| Service | Purpose |
|---------|---------|
| **Lambda** | Core scraper and keyword filter logic |
| **DynamoDB** | Deduplication store with TTL auto-cleanup |
| **SNS** | Email alert delivery |
| **EventBridge Scheduler** | Cron trigger every 3 days at 11 PM ET |
| **IAM** | Least-privilege roles for Lambda and EventBridge |
| **CloudWatch Logs** | Execution logging and monitoring |

## Target Facebook Groups

| Group | URL |
|-------|-----|
| Atlanta Real Estate Wholesalers | `/groups/atlant.realestate.wholesalers` |
| GA Off Market Properties | `/groups/georgiaoffmarketproperties` |
| Atlanta GA Real Estate Investing | `/groups/atlanta.ga.real.estate.investing` |
| Group 353876517547400 | `/groups/353876517547400` |
| Group 364263283590058 | `/groups/364263283590058` |

## Deal Keywords

**Positive keywords**

`must sell`, `need to sell`, `motivated`, `as-is`, `inherited`, `estate sale`, `probate`, `foreclosure`, `pre-foreclosure`, `divorce`, `vacant`, `abandoned`, `fixer upper`, `tlc`, `off market`, `wholesale`, `fsbo`, `below market`, `cash only`

**Negative keywords**

`just listed`, `new listing`, `mls#`, `listing price`, `days on market`, `realtor`, `real estate agent`, `keller williams`, `re/max`, `coldwell banker`, `exp realty`, `looking to buy`, `investor looking`, `bird dog`

## Cost

| Service | Cost |
|---------|------|
| ScrapeCreators (5,000 credits) | $10 for roughly 2+ years at current schedule |
| Lambda | $0 under free tier |
| DynamoDB | $0 under free tier |
| EventBridge | $0 under free tier |
| SNS Email | $0 under free tier |
| **Total** | **About $0-2 per month** |

## Project Structure

```text
.
├── lambda_function.py
├── main.tf
├── terraform.tfvars.example
├── docs/
│   ├── manual-setup.md
│   └── screenshots/
└── README.md
```

## Documentation

- Full AWS console walkthrough with screenshots: [docs/manual-setup.md](docs/manual-setup.md)
- Infrastructure deployment option: Terraform via `main.tf`

## Quick Deploy With Terraform

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install)
- AWS CLI configured with `aws configure`
- A [ScrapeCreators](https://scrapecreators.com) account and API key

### 1. Build the requests Lambda layer

```bash
mkdir python
pip3 install requests -t python/
zip -r requests-layer.zip python/
```

Place `requests-layer.zip` in the same folder as `main.tf`.

### 2. Set variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then fill in:

```hcl
scrapecreators_api_key = "your_key_here"
alert_email            = "you@example.com"
```

Do not commit `terraform.tfvars`.

### 3. Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 4. Confirm the SNS email subscription

AWS sends a confirmation email before alerts begin.

## Validation

After deployment, you should be able to verify all three outcomes:

- Lambda test runs successfully
- SNS emails arrive in your inbox
- DynamoDB stores deduplicated post records

| Lambda Test | Email Alerts |
|---|---|
| ![Lambda test](docs/screenshots/21-lambda-test-success.png) | ![Email alerts](docs/screenshots/22-email-alerts-received.png) |

| DynamoDB Items | CloudWatch Logs |
|---|---|
| ![DynamoDB items](docs/screenshots/23-dynamodb-items-stored.png) | ![CloudWatch logs](docs/screenshots/24-cloudwatch-logs.png) |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `SCRAPECREATORS_API_KEY` | API key from ScrapeCreators |
| `FB_GROUP_URLS` | Comma-separated Facebook group URLs |
| `SNS_TOPIC_ARN` | SNS topic ARN for alerts |
| `DYNAMODB_TABLE` | DynamoDB table name, usually `fb-deal-posts` |

All sensitive values live in Lambda environment variables rather than source code.

## Extending This Project

| Extension | Description |
|-----------|-------------|
| **SES Daily Digest** | Replace per-post SNS alerts with one nightly summary |
| **API Gateway + React** | Add a web dashboard to review and track leads |
| **Bedrock / Claude API** | Add AI-based lead scoring and reasoning |
| **S3 Archive** | Save all scraped posts as JSON for later analysis |

## Security

- Credentials are stored in Lambda environment variables only
- `terraform.tfvars` is gitignored
- AWS account ID is fetched dynamically via `data.aws_caller_identity`
- IAM roles can be narrowed beyond the current broad managed policies for production use

## About

Built for **Clearpath Property Group**, a real estate wholesaling operation in the Atlanta and Gwinnett County, Georgia area.

This project also serves as a portfolio-ready AWS case study aligned with topics covered on the AWS Solutions Architect Associate exam.
