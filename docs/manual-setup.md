# Manual AWS Setup Walkthrough

This guide shows how to deploy the project manually in the AWS console using the same configuration shown in the screenshots included with this repository.

## 1. Create the DynamoDB table

Create a table named `fb-deal-posts` with:

- Partition key: `post_id`
- Type: `String`
- Default settings enabled

![Create DynamoDB table](screenshots/01-dynamodb-create-table.png)

## 2. Enable DynamoDB TTL

Turn on Time to Live and use the attribute name:

- `expires_at`

This lets old post records expire automatically after 30 days.

![Enable DynamoDB TTL](screenshots/02-dynamodb-enable-ttl.png)

## 3. Create the SNS topic

Create a standard SNS topic named:

- `deal-alerts`

This topic will deliver the email notifications.

![Create SNS topic](screenshots/03-sns-create-topic.png)

## 4. Add an email subscription

Create an SNS subscription using:

- Protocol: `Email`
- Endpoint: your email address

![Create SNS email subscription](screenshots/04-sns-create-email-subscription.png)

## 5. Confirm the subscription from your inbox

AWS sends a confirmation email immediately after you create the subscription. Open it and click the confirmation link.

![SNS confirmation email](screenshots/05-sns-confirmation-email.png)

After confirmation, SNS shows the subscription as active.

![SNS subscription confirmed](screenshots/06-sns-subscription-confirmed.png)

## 6. Optional: review the SNS access policy

If you need to troubleshoot publish permissions, inspect the topic access policy. This screenshot shows the area where the principal and allowed SNS actions appear.

![SNS access policy snippet](screenshots/07-iam-policy-sns-publish-snippet.png)

## 7. Create the Lambda IAM role

In IAM, create a new role with:

- Trusted entity type: `AWS service`
- Use case: `Lambda`

![Select Lambda trusted entity](screenshots/08-iam-role-select-trusted-entity.png)

On the review screen, name the role something like:

- `deal-finder-lambda-role`

The screenshot also shows the broad managed policies used in this build:

- `AmazonDynamoDBFullAccess`
- `AmazonSNSFullAccess`
- `AWSLambdaBasicExecutionRole`

![Review IAM role](screenshots/09-iam-role-review-permissions.png)

## 8. Create the Lambda function

Create a Lambda function named:

- `fb-deal-finder`

Use:

- Runtime: Python
- Existing execution role: `deal-finder-lambda-role`

![Create Lambda function](screenshots/10-lambda-create-function.png)

## 9. Configure Lambda environment variables

Add the following environment variables:

- `SCRAPECREATORS_API_KEY`
- `FB_GROUP_URLS`
- `SNS_TOPIC_ARN`
- `DYNAMODB_TABLE`

![Lambda environment variables](screenshots/11-lambda-environment-variables.png)

You do not need to replace the bracketed variable names inside the code. The code reads the real values from Lambda environment variables at runtime.

![Environment variable note](screenshots/13-lambda-env-vars-note.png)

## 10. Paste the scraper code into Lambda

Upload or paste `lambda_function.py` into the function editor.

![Lambda function editor](screenshots/12-lambda-function-editor.png)

## 11. Create the requests layer

Package `requests` locally into `requests-layer.zip`, then create a Lambda layer named:

- `requests-layer`

The screenshot shows the layer configured as a zip upload with Python runtimes selected.

![Create Lambda layer](screenshots/14-lambda-create-layer.png)

## 12. Attach the layer to the function

Inside the Lambda function, choose `Add a layer`, select `Custom layers`, then pick:

- Layer: `requests-layer`
- Version: `1`

![Add layer dialog](screenshots/15-lambda-add-layer-dialog.png)

![Select layer version](screenshots/16-lambda-select-layer-version.png)

## 13. Create the EventBridge schedule

Create a recurring EventBridge schedule named:

- `fb-deal-finder-schedule`

Use:

- Time zone: `America/New_York`
- Cron-based schedule
- `0 23 */3 * ? *`

That runs the scraper at 11 PM Eastern every 3 days.

![Create EventBridge schedule](screenshots/17-eventbridge-create-schedule.png)

The cron explainer below shows how the day-of-month field `*/3` works.

![Cron explainer](screenshots/18-eventbridge-cron-explainer.png)

## 14. Set the EventBridge target

Choose AWS Lambda as the target and select:

- Function: `fb-deal-finder`

![Select EventBridge target](screenshots/19-eventbridge-select-target.png)

![Lambda target selected](screenshots/20-eventbridge-target-lambda-selected.png)

## 15. Test the Lambda function

Create a simple test event such as `{}` and run the function. A successful run should show a `200` status and execution logs.

![Lambda test success](screenshots/21-lambda-test-success.png)

## 16. Confirm the end-to-end results

If everything is wired correctly, you should see:

- SNS alert emails in your inbox
- post records stored in DynamoDB
- detailed logs in CloudWatch

![Email alerts received](screenshots/22-email-alerts-received.png)

![DynamoDB items stored](screenshots/23-dynamodb-items-stored.png)

![CloudWatch logs](screenshots/24-cloudwatch-logs.png)

## Notes

- The current setup favors speed and clarity over least-privilege IAM. For production use, narrow the permissions.
- The `terraform` files in the repo are the cleaner long-term path if you want repeatable infrastructure.
- If SNS works but no emails arrive, re-check subscription confirmation first.
