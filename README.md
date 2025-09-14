# CloudFront Log Analysis Tool

A colorful command-line tool for analyzing AWS CloudFront logs with real-time filtering, IP tracing, and beautiful output formatting.

## Features

- **Smart Caching**: Downloads only missing time ranges, reuses existing data
- **Real Client IPs**: Extracts actual end-user IPs from CloudFront logs

## Setup

1. **Copy the configuration template:**
   ```bash
   cp cloudfront_logs.conf.template cloudfront_logs.conf
   ```

2. **Edit `cloudfront_logs.conf` with your actual AWS S3 bucket names and paths**

3. **Ensure AWS CLI is configured with appropriate permissions**

## Usage

### Regular Mode
```bash
./cloudfront_logs.sh <endpoint1>[,endpoint2,...] <minutes> [--env <environment>] [--cache|--fresh]
```

### IP Tracing Mode
```bash
./cloudfront_logs.sh --ip <ip_address> <endpoint1>[,endpoint2,...] <minutes> [--env <environment>] [--cache|--fresh]
```

## Arguments

- **endpoint**: API endpoint(s) to filter. Use comma-separated for multiple:
  - Single: `/api`, `/marketplace`, `/auth`
  - Multiple: `/marketplace,/cart,/auth`
- **minutes**: Number of minutes back to search (required for all modes)
- **--ip**: IP address to trace (IP mode only)

## Options

- **--env**: Environment: `prod` (default), `staging`, `dev`
- **--cache**: Use smart caching (downloads only missing data)
- **--fresh**: Force fresh download (ignore cache completely)

## Output Columns

- **EDT Time**: Request timestamp in your local timezone (8-char fixed width)
- **Client_IP**: Real client IP address (15-char fixed width, colorized)
- **Status**: HTTP response status code (colorized)
- **Method**: HTTP request method
- **Bytes**: Response size in bytes
- **Endpoint**: API endpoint path (colorized)
- **User_Agent**: Browser/client user agent (truncated, colorized)

## Status Colors

- 🟢 **200/201/204**: Success responses
- 🔵 **304**: Not modified
- 🟡 **401/403**: Authentication/authorization errors
- 🔴 **4xx/5xx**: Other client/server errors

## Examples

### Regular Mode
```bash
# Single endpoint: /api requests (last 60 minutes)
./cloudfront_logs.sh /api 60

# Multiple endpoints: marketplace + auth (30 min)
./cloudfront_logs.sh /marketplace,/auth 30

# Three endpoints with caching (2 hours)
./cloudfront_logs.sh /api,/auth,/marketplace 120 --cache

# Staging environment with fresh download
./cloudfront_logs.sh /health 15 --env staging --fresh
```

### IP Tracing Mode
```bash
# Trace IP across single endpoint (last 60 minutes)
./cloudfront_logs.sh --ip 192.168.1.100 /marketplace 60

# Trace IP across multiple endpoints (30 minutes)
./cloudfront_logs.sh --ip 10.0.0.50 /api,/auth 30 --cache

# Trace IP in staging environment
./cloudfront_logs.sh --ip 203.0.113.45 /notifications 15 --env staging
```

## Environments

- **prod**: Production logs (default)
- **staging**: Staging environment logs  
- **dev**: Development environment logs

## Cache Behavior

- Cache files stored as `cloudfront_logs_<env>_cache.log`
- **--cache**: Use cached data when available, download missing ranges
- **--fresh**: Force complete fresh download, update cache
- **No flag**: Use existing cache if available, smart caching by default
- **Status indicators**: Shows 'cached', 'smart cache', or 'fresh data'
- Smart cache automatically detects missing time ranges and downloads only needed data
- IP tracing works with all cache modes

## Requirements

- AWS CLI configured with S3 access
- Bash shell
- Standard Unix utilities (awk, sed, sort, etc.)

## Notes

- **Timeframe Required**: All queries must specify a time range to prevent accidental large data searches
- **Real Client IPs**: Unlike ALB logs, CloudFront logs show actual end-user IPs
- **Smart Caching**: Automatically uses existing cache and downloads missing data when needed
- **HTTP Method Support**: Extracts endpoints from all HTTP methods (GET, POST, PUT, PATCH, DELETE, OPTIONS)
- **Fixed-Width Columns**: Time and IP columns use consistent spacing for better readability
- Times automatically converted from UTC to local timezone
- Results sorted chronologically
- Multiple endpoints show combined results with endpoint column
- IP mode processes most selective filter first for optimal performance

## Help

For complete usage information:
```bash
./cloudfront_logs.sh --help
```
