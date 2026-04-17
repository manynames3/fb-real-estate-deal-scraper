import json
import os
import boto3
import requests
import hashlib
import time
from datetime import datetime, timezone

# ── CONFIG ─────────────────────────────────────────────────
API_KEY        = os.environ['SCRAPECREATORS_API_KEY']
GROUP_URLS     = os.environ['FB_GROUP_URLS'].split(',')
SNS_TOPIC_ARN  = os.environ['SNS_TOPIC_ARN']
DYNAMODB_TABLE = os.environ['DYNAMODB_TABLE']
REGION         = os.environ.get('AWS_REGION', 'us-east-1')

DEAL_KEYWORDS = [
    # Motivated seller
    'must sell', 'need to sell', 'motivated', 'cash buyer',
    'cash offer', 'as-is', 'as is', 'sell fast', 'quick sale',
    'fast close', 'price reduced', 'priced to sell',
    # Distress
    'inherited', 'estate sale', 'probate', 'behind on payments',
    'foreclosure', 'pre-foreclosure', 'divorce', 'relocating',
    'moving out of state', 'tired landlord', 'job loss',
    # Condition
    'fixer', 'fixer upper', 'needs work', 'needs repairs',
    'tlc', 'handyman special', 'distressed', 'fire damage',
    'vacant', 'abandoned', 'hoarder',
    # Deal signals
    'below market', 'wholesale', 'off market', 'assignment',
    'fsbo', 'for sale by owner', 'no realtor', 'no agent',
    'deep discount', 'cash only',
    # GA/SC/MA markets
    'gwinnett', 'dekalb', 'forsyth', 'hall county',
    'suwanee', 'lawrenceville', 'buford', 'duluth', 'atlanta',
    'greenville sc', 'spartanburg', 'upstate sc',
    'medford ma', 'boston'
]

NEGATIVE_KEYWORDS = [
    # MLS / Listed properties
    'just listed', 'new listing', 'listed on mls', 'mls#', 'mls #',
    'listed at', 'list price', 'listing price', 'days on market',
    'active listing', 'back on market',
    # Realtor / Agent signals
    'realtor', 'real estate agent', 'licensed agent', 'listing agent',
    'buyer agent', 'sellers agent', "i'm an agent", 'i am an agent',
    'represented by', 'call your agent', 'contact your realtor',
    'keller williams', 're/max', 'remax', 'coldwell banker',
    'berkshire hathaway', 'exp realty', 'compass', 'century 21',
    # Retail pricing
    'full price', 'priced at market',
    # Buyer-side posts
    'looking to buy', 'looking for a home', 'seeking property',
    'i am a buyer', 'cash buyer looking', 'investor looking',
    'wholesaler looking', 'looking for deals', 'seeking deals',
    # Networking noise
    'referral fee', 'bird dog', 'looking for jv',
]

# ── AWS CLIENTS ─────────────────────────────────────────────
dynamodb = boto3.resource('dynamodb', region_name=REGION)
table    = dynamodb.Table(DYNAMODB_TABLE)
sns      = boto3.client('sns', region_name=REGION)


def generate_post_id(post):
    raw = post.get('id') or post.get('url') or post.get('text', '')[:100]
    return hashlib.sha256(raw.encode()).hexdigest()[:32]


def is_new_post(post_id):
    try:
        resp = table.get_item(Key={'post_id': post_id})
        return 'Item' not in resp
    except Exception as e:
        print(f'DynamoDB read error: {e}')
        return True


def save_post(post_id, text, url):
    expires_at = int(time.time()) + (30 * 24 * 60 * 60)
    try:
        table.put_item(Item={
            'post_id':    post_id,
            'text':       text[:500],
            'url':        url,
            'seen_at':    datetime.now(timezone.utc).isoformat(),
            'expires_at': expires_at
        })
    except Exception as e:
        print(f'DynamoDB write error: {e}')


def score_post(text):
    t = text.lower() if text else ''
    # Check negative keywords first — skip if any match
    if any(neg in t for neg in NEGATIVE_KEYWORDS):
        return [], 0
    matched = [kw for kw in DEAL_KEYWORDS if kw in t]
    return matched, len(matched)


def send_alert(post, matched, group_url):
    text     = post.get('text') or ''
    text     = text[:600]
    post_url = post.get('url', '')
    date     = post.get('date', 'Unknown')
    author   = post.get('author', {}).get('name', 'Unknown')                if isinstance(post.get('author'), dict)                else str(post.get('author', 'Unknown'))

    message = (
        f"🏠 DEAL ALERT — Clearpath Property Group\n\n"
        f"👤 BY: {author}\n"
        f"📅 DATE: {date}\n\n"
        f"💬 POST:\n{text}\n\n"
        f"🔑 KEYWORDS: {', '.join(matched)}\n\n"
        f"🔗 LINK: {post_url}\n"
        f"📡 GROUP: {group_url}\n"
        f"---\nClearpath AWS Deal Scout"
    )
    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject='🏠 New Deal Alert — FB Group',
            Message=message
        )
        print(f'  ✅ Alert sent: {text[:60]}')
    except Exception as e:
        print(f'  SNS error: {e}')


def fetch_group_posts(url):
    try:
        r = requests.get(
            'https://api.scrapecreators.com/v1/facebook/group/posts',
            headers={'x-api-key': API_KEY},
            params={'url': url.strip()},
            timeout=15
        )
        r.raise_for_status()
        return r.json().get('posts', [])
    except Exception as e:
        print(f'  ScrapeCreators error: {e}')
        return []


def process_group(url):
    print(f'\nChecking: {url}')
    posts = fetch_group_posts(url)
    print(f'  Fetched {len(posts)} posts')

    sent = 0
    for post in posts:
        pid            = generate_post_id(post)
        text           = post.get('text') or ''
        matched, score = score_post(text)

        if score == 0:
            continue

        if not is_new_post(pid):
            print(f'  Already seen {pid[:8]}... skipping')
            continue

        print(f'  🚨 New deal! Score={score} | Keywords={matched}')
        save_post(pid, text, post.get('url', ''))
        send_alert(post, matched, url)
        sent += 1

    return sent


def lambda_handler(event, context):
    print(f'FB Deal Finder — {datetime.now(timezone.utc).isoformat()}')
    print(f'Monitoring {len(GROUP_URLS)} groups')

    total = sum(process_group(u) for u in GROUP_URLS if u.strip())

    print(f'\nDone. Total alerts sent: {total}')
    return {
        'statusCode': 200,
        'body': json.dumps({'alerts_sent': total})
    }
