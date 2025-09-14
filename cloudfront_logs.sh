#!/usr/bin/env bash

# CloudFront Log Analysis Tool
# Analyzes AWS CloudFront logs with real-time filtering, IP tracing, and beautiful output formatting

# Configuration file
CONFIG_FILE="cloudfront_logs.conf"

# Function to build grep pattern for multiple endpoints
build_endpoint_pattern() {
    local endpoints="$1"
    if [[ "$endpoints" == *","* ]]; then
        echo "$endpoints" | sed 's/,/|/g'
    else
        echo "$endpoints"
    fi
}

# Function to process CloudFront logs
process_logs() {
    awk -F'\t' '{
      # CloudFront log format (tab-separated):
      # date time x-edge-location sc-bytes c-ip cs-method cs(Host) cs-uri-stem sc-status cs(Referer) cs(User-Agent) cs-uri-query cs(Cookie) x-edge-result-type x-edge-request-id x-host-header cs-protocol cs-bytes time-taken x-forwarded-for ssl-protocol ssl-cipher x-edge-response-result-type cs-protocol-version fle-status fle-encrypted-fields c-port time-to-first-byte x-edge-detailed-result-type sc-content-type sc-content-len sc-range-start sc-range-end
      
      # Skip comment lines
      if ($0 ~ /^#/) next
      
      date = $1
      time = $2
      client_ip = $5
      method = $6
      host = $7
      uri_stem = $8
      status = $9
      referrer = $10
      user_agent = $11
      bytes = $4
      
      # Convert date/time to local time
      datetime = date " " time
      cmd = "date -d \"" datetime " UTC\" \"+%H:%M:%S\""
      cmd | getline local_time
      close(cmd)
      
      # Decode URL-encoded user agent
      gsub(/%20/, " ", user_agent)
      gsub(/%28/, "(", user_agent)
      gsub(/%29/, ")", user_agent)
      gsub(/%2C/, ",", user_agent)
      gsub(/%3B/, ";", user_agent)
      
      # Truncate user agent
      if (length(user_agent) > 50) {
        user_agent = substr(user_agent, 1, 47) "..."
      }
      
      # Color codes
      red = "\033[31m"
      green = "\033[32m"
      yellow = "\033[33m"
      blue = "\033[34m"
      cyan = "\033[36m"
      salmon = "\033[38;5;210m"
      purple = "\033[35m"
      bright_green = "\033[92m"
      bold = "\033[1m"
      reset = "\033[0m"
      
      # Color status codes
      if (status == "200" || status == "201" || status == "204") {
        status_color = green bold status reset
      } else if (status == "304") {
        status_color = blue status reset
      } else if (status == "401" || status == "403") {
        status_color = yellow status reset
      } else if (status >= "400") {
        status_color = red bold status reset
      } else {
        status_color = status
      }
      
      # Color IP addresses (different colors for different ranges)
      if (match(client_ip, /^192\.168\.|^10\.|^172\.(1[6-9]|2[0-9]|3[01])\./)) {
        ip_color = yellow client_ip reset  # Private IPs
      } else {
        ip_color = salmon client_ip reset  # Public IPs
      }
      
      # Color endpoint
      endpoint_color = cyan uri_stem reset
      
      # Color user agent
      ua_color = bright_green user_agent reset
      
      # Color method
      method_color = purple method reset
      
      printf "%-8s | %-15s | %s | %s | %-8s | %s | %s\n", local_time, ip_color, status_color, method_color, bytes, endpoint_color, ua_color
    }' | sort
}

get_available_environments() {
    local envs=""
    if [ -n "${PROD_S3_BUCKET:-}" ]; then envs="${envs}prod "; fi
    if [ -n "${STAGING_S3_BUCKET:-}" ]; then envs="${envs}staging "; fi
    if [ -n "${DEV_S3_BUCKET:-}" ]; then envs="${envs}dev "; fi
    echo "${envs% }"
}

show_help() {
    local available_envs=$(get_available_environments)
    local default_env=$(echo $available_envs | cut -d' ' -f1)
    
    echo -e "\033[1m\033[36mCloudFront Log Analysis Tool\033[0m"
    echo ""
    echo -e "\033[33mUSAGE:\033[0m"
    echo -e "    \033[32m$0\033[0m \033[36m<endpoint1>[,endpoint2,...]\033[0m \033[35m<minutes>\033[0m [\033[31m--env\033[0m \033[34m<environment>\033[0m] [\033[31m--cache\033[0m|\033[31m--fresh\033[0m]"
    echo -e "    \033[32m$0\033[0m \033[31m--ip\033[0m \033[91m<ip_address>\033[0m \033[36m<endpoint1>[,endpoint2,...]\033[0m \033[35m<minutes>\033[0m [\033[31m--env\033[0m \033[34m<environment>\033[0m] [\033[31m--cache\033[0m|\033[31m--fresh\033[0m]"
    echo ""
    echo -e "\033[33mDESCRIPTION:\033[0m"
    echo "    Analyzes AWS CloudFront logs for specific API endpoints."
    echo "    Shows real client IPs (not edge server IPs)."
    echo "    IP mode traces specific IP addresses across endpoints."
    echo ""
    echo -e "\033[33mARGUMENTS:\033[0m"
    echo -e "    \033[35mendpoint\033[0m     API endpoint(s) to filter. Use comma-separated for multiple:"
    echo "                   Single: /api, /marketplace, /auth"
    echo "                   Multiple: /marketplace,/cart,/auth"
    echo -e "    \033[35mminutes\033[0m      Number of minutes back to search (required for all modes)"
    echo -e "    \033[35m--ip\033[0m         IP address to trace (IP mode only)"
    echo ""
    echo -e "\033[33mOPTIONS:\033[0m"
    if [ -n "$available_envs" ]; then
        echo -e "    \033[32m--env\033[0m        Environment: ${available_envs} (default: ${default_env})"
    else
        echo -e "    \033[32m--env\033[0m        Environment: (none configured)"
    fi
    echo -e "    \033[32m--cache\033[0m      Use smart caching (downloads only missing data)"
    echo -e "    \033[32m--fresh\033[0m      Force fresh download (ignore cache completely)"
    echo ""
    echo -e "\033[33mOUTPUT COLUMNS:\033[0m"
    echo -e "    \033[31mEDT Time\033[0m: Request timestamp in your local timezone"
    echo -e "    \033[91mClient_IP\033[0m: Real client IP address (colorized)"
    echo -e "    \033[32mStatus\033[0m: HTTP response status code (colorized)"
    echo -e "    \033[35mMethod\033[0m: HTTP request method"
    echo -e "    \033[33mBytes\033[0m: Response size in bytes"
    echo -e "    \033[36mEndpoint\033[0m: API endpoint path (colorized)"
    echo -e "    \033[92mUser_Agent\033[0m: Browser/client user agent (truncated, colorized)"
    echo ""
    echo -e "\033[33mSTATUS COLORS:\033[0m"
    echo -e "    \033[32m\033[1m200/201/204\033[0m: Success responses"
    echo -e "    \033[34m304\033[0m: Not modified"
    echo -e "    \033[33m401/403\033[0m: Authentication/authorization errors"
    echo -e "    \033[31m\033[1m4xx/5xx\033[0m: Other client/server errors"
    echo ""
    echo -e "\033[33mEXAMPLES:\033[0m"
    echo "    # Single endpoint (last 60 minutes)"
    echo "    $0 /api 60"
    echo ""
    echo "    # Multiple endpoints (30 minutes)"
    echo "    $0 /api,/auth,/marketplace 30"
    echo ""
    echo "    # IP tracing across endpoint"
    echo "    $0 --ip 192.168.1.100 /api 60"
    echo ""
    echo "    # Staging environment with caching"
    echo "    $0 /health 15 --env staging --cache"
    echo ""
    echo -e "\033[33mCACHE BEHAVIOR:\033[0m"
    echo "    - Cache files stored as cloudfront_logs_<env>_cache.log"
    echo "    - --cache: Use cached data when available, download missing ranges"
    echo "    - --fresh: Force complete fresh download, update cache"
    echo "    - No flag: Use existing cache if available, smart caching by default"
    echo "    - Status shows: 'cached', 'smart cache', or 'fresh data'"
    echo ""
    echo -e "\033[33mNOTES:\033[0m"
    echo "    - Requires AWS CLI configured with S3 access"
    echo "    - Shows real client IPs (not CloudFront edge server IPs)"
    echo "    - Timeframe required for all queries to prevent large data searches"
    echo "    - Results sorted chronologically with colorized output"
    echo ""
}

# Load configuration first
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_help
    exit 0
fi

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Configuration file $CONFIG_FILE not found!"
    echo "Copy cloudfront_logs.conf.template to cloudfront_logs.conf and configure your S3 bucket paths."
    exit 1
fi

source "$CONFIG_FILE"

# Parse arguments
IP_MODE=false
IP_ADDRESS=""
ENDPOINT=""
MINUTES_BACK=""
ENV="prod"
USE_CACHE=false
FORCE_FRESH=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --ip)
            IP_MODE=true
            IP_ADDRESS="$2"
            shift 2
            ;;
        --env)
            ENV="$2"
            shift 2
            ;;
        --cache)
            USE_CACHE=true
            shift
            ;;
        --fresh)
            FORCE_FRESH=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            echo "❌ Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
        *)
            if [ -z "$ENDPOINT" ]; then
                ENDPOINT="$1"
            elif [ -z "$MINUTES_BACK" ]; then
                MINUTES_BACK="$1"
            else
                echo "❌ Too many arguments: $1"
                echo "Use --help for usage information."
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate required arguments
if [ -z "$ENDPOINT" ] || [ -z "$MINUTES_BACK" ]; then
    echo "❌ Missing required arguments: endpoint and minutes"
    echo "Use --help for usage information."
    exit 1
fi

if [ "$IP_MODE" = true ] && [ -z "$IP_ADDRESS" ]; then
    echo "❌ IP address required for IP tracing mode"
    exit 1
fi

if ! [[ "$MINUTES_BACK" =~ ^[0-9]+$ ]]; then
    echo "❌ Minutes must be a positive integer"
    exit 1
fi

# Set S3 bucket and path based on environment
case $ENV in
    prod)
        S3_BUCKET="${PROD_S3_BUCKET:-}"
        S3_PATH="${PROD_S3_PATH:-}"
        ;;
    staging)
        S3_BUCKET="${STAGING_S3_BUCKET:-}"
        S3_PATH="${STAGING_S3_PATH:-}"
        ;;
    dev)
        S3_BUCKET="${DEV_S3_BUCKET:-}"
        S3_PATH="${DEV_S3_PATH:-}"
        ;;
    *)
        echo "❌ Invalid environment: $ENV (use prod, staging, or dev)"
        exit 1
        ;;
esac

if [ -z "$S3_BUCKET" ] || [ -z "$S3_PATH" ]; then
    echo "❌ S3 bucket/path not configured for environment: $ENV"
    exit 1
fi

# Calculate time range
MINUTES_AGO=$(date -u -d "$MINUTES_BACK minutes ago" '+%Y-%m-%dT%H:%M:%SZ')
NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
LOCAL_TZ=$(date '+%Z')
TODAY=$(date -u '+%Y/%m/%d')

# Cache file
CACHE_FILE="cloudfront_logs_${ENV}_cache.log"
CACHE_MODE="fresh data"

# Smart caching logic (same as ALB)
if [ "$FORCE_FRESH" = true ]; then
    USE_CACHE=false
    CACHE_MODE="fresh data"
elif [ -f "$CACHE_FILE" ]; then
    USE_CACHE=true
    CACHE_NEEDS_UPDATE=false
    
    if [ ! -s "$CACHE_FILE" ]; then
        echo "📥 Cache empty or missing, downloading fresh data..."
        CACHE_NEEDS_UPDATE=true
        CACHE_MODE="fresh data"
    else
        # Check cache coverage (simplified)
        CACHE_OLDEST=$(head -1 "$CACHE_FILE" | awk '{print $2}')
        CACHE_NEWEST=$(tail -1 "$CACHE_FILE" | awk '{print $2}')
        
        if [[ "$CACHE_OLDEST" > "$MINUTES_AGO" ]] || [[ "$CACHE_NEWEST" < "$MINUTES_AGO" ]]; then
            echo "📥 Cache doesn't cover requested time range, downloading additional data..."
            CACHE_NEEDS_UPDATE=true
            CACHE_MODE="smart cache"
        else
            echo "📂 Using cache: $CACHE_FILE ($ENV environment)"
            CACHE_MODE="cached"
        fi
    fi
else
    USE_CACHE=false
    CACHE_MODE="fresh data"
fi

# Status message
if [ "$IP_MODE" = true ]; then
    echo -e "🔍 Tracing IP \033[91m$IP_ADDRESS\033[0m across \033[36m$ENDPOINT\033[0m from \033[31m$MINUTES_AGO\033[0m to now (\033[32m$ENV\033[0m environment, \033[35m$CACHE_MODE\033[0m):"
else
    echo -e "🔍 All \033[36m$ENDPOINT\033[0m requests from \033[31m$MINUTES_AGO\033[0m to now (times in \033[33m$LOCAL_TZ\033[0m, \033[32m$ENV\033[0m environment, \033[35m$CACHE_MODE\033[0m):"
fi

# Headers
echo -e "• \033[31m$LOCAL_TZ Time\033[0m: Local timestamp"
echo -e "• \033[91mClient_IP\033[0m: Real client IP address"
echo -e "• \033[32mStatus\033[0m: HTTP response status code"
echo -e "• \033[35mMethod\033[0m: HTTP request method"
echo -e "• \033[33mBytes\033[0m: Response size in bytes"
echo -e "• \033[36mEndpoint\033[0m: API endpoint path"
echo -e "• \033[92mUser_Agent\033[0m: Browser info (truncated)"
echo -e "Status Colors: \033[32m\033[1m200/201/204\033[0m \033[34m304\033[0m \033[33m401/403\033[0m \033[31m\033[1m4xx/5xx\033[0m"
echo -e "\033[31m$LOCAL_TZ Time\033[0m | \033[91mClient_IP\033[0m       | \033[32mStatus\033[0m | \033[35mMethod\033[0m | \033[33mBytes\033[0m    | \033[36mEndpoint\033[0m | \033[92mUser_Agent\033[0m"
echo "--------------------------------------------------------------------------------------------------------"

# Download and process logs
if [ "$USE_CACHE" = true ] && [ "$CACHE_NEEDS_UPDATE" = false ]; then
    # Use existing cache
    LOG_DATA=$(cat "$CACHE_FILE")
else
    # Download fresh data
    echo "📊 Downloading fresh CloudFront logs from S3..."
    
    # Get log files from S3 (CloudFront format: E2LUCT8WBU2LSL.2025-09-14-00.651a4e58.gz)
    CUTOFF_TIME=$(date -u -d "$MINUTES_BACK minutes ago" '+%Y-%m-%d-%H')
    
    LOG_FILES=$(aws s3 ls s3://$S3_BUCKET/$S3_PATH/ | awk -v cutoff="$CUTOFF_TIME" '{
        if (match($4, /[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}/)) {
            timestamp = substr($4, RSTART, 13)
            if (timestamp >= cutoff) {
                print $4
            }
        }
    }')
    
    TOTAL_FILES=$(echo "$LOG_FILES" | grep -c .)
    
    if [ "$TOTAL_FILES" -eq 0 ]; then
        echo "⚠️  No recent log files found."
        exit 0
    fi
    
    echo "📁 Found $TOTAL_FILES relevant log files (timestamp >= $CUTOFF_TIME)"
    
    # Download files sequentially to avoid hanging
    TEMP_FILE=$(mktemp)
    
    echo "$LOG_FILES" | while read -r file; do
        [ -n "$file" ] && aws s3 cp s3://$S3_BUCKET/$S3_PATH/$file - 2>/dev/null | zcat 2>/dev/null >> "$TEMP_FILE"
    done
    
    printf "\r📥 Downloaded %d files                    \n" "$TOTAL_FILES" >&2
    
    # Update cache
    if [ "$USE_CACHE" = true ]; then
        if [ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ]; then
            cat "$CACHE_FILE" "$TEMP_FILE" | sort -u -k1,2 > "${CACHE_FILE}.tmp"
        else
            sort -k1,2 "$TEMP_FILE" > "${CACHE_FILE}.tmp"
        fi
        mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
        LOG_DATA=$(cat "$CACHE_FILE")
    else
        sort -k1,2 "$TEMP_FILE" > "$CACHE_FILE"
        LOG_DATA=$(cat "$TEMP_FILE")
    fi
    
    rm -f "$TEMP_FILE"
fi

# Filter and process logs
ENDPOINT_PATTERN=$(build_endpoint_pattern "$ENDPOINT")

if [ "$IP_MODE" = true ]; then
    echo "$LOG_DATA" | grep -E "$ENDPOINT_PATTERN" | awk -F'\t' -v ip="$IP_ADDRESS" '$5 == ip' | process_logs
else
    echo "$LOG_DATA" | grep -E "$ENDPOINT_PATTERN" | process_logs
fi

echo ""
echo "✅ Processing complete"
