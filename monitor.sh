#!/bin/bash

# --- Configuration ---
# Read from environment variables, falling back to hardcoded defaults
ENDPOINT="${ENDPOINT:-http://cleanuparr:11011/api/configuration/queue_cleaner}"
INTERVAL="${INTERVAL:-600}" # 10 minutes (600 seconds)
SUCCESS_THRESHOLD="${SUCCESS_THRESHOLD:-2}" # Consecutive successful checks required to ENABLE the endpoint

# Hosts for connectivity check (requires iputils/ping)
CHECK_HOST_1="1.1.1.1"
CHECK_HOST_2="8.8.8.8"

# Tracks the last status sent to the API to prevent redundant calls
LAST_STATUS="initial"

# Tracks consecutive successful checks for the enabling hysteresis
CONSECUTIVE_SUCCESS_COUNT=0

# --- Functions ---

# Helper function for logging with timestamp
log() {
    echo "$(date +%T) - $1"
}

# Function for clean exit upon receiving SIGINT (Ctrl-C) or SIGTERM
cleanup() {
    log "Monitor received termination signal. Exiting gracefully."
    exit 0
}
trap cleanup SIGINT SIGTERM

# Function checks connectivity (1.1.1.1 OR 8.8.8.8)
check_internet() {
    # Increase ping count to 3 for more reliable connectivity check.
    # Short-circuit logic: Pings CHECK_HOST_1, if fail, pings CHECK_HOST_2.
    # If either succeeds, $? is 0. Returns "true" or "false" based on exit code.
    (ping -c 3 -W 2 "$CHECK_HOST_1" || ping -c 3 -W 2 "$CHECK_HOST_2") >/dev/null 2>&1 && echo "true" || echo "false"
}

# Function sends the PUT request (Read-Modify-Write Pattern)
# Returns 0 on successful API update, 1 on failure.
update_endpoint() {
    local status="$1"
    local JSON_PAYLOAD
    local CURL_CODE
    local CONFIG_JSON

    log "Attempting to send status: '$status'"

    # 1. GET the current configuration
    CONFIG_JSON=$(curl --compressed -s -X GET "$ENDPOINT" -H 'Accept: application/json')
    CURL_CODE=$?

    if [[ "$CURL_CODE" -ne 0 ]]; then
        log "ERROR: GET failed. Curl exit code: $CURL_CODE. Check endpoint URL or network."
        return 1 # Indicate failure
    fi

    # 2. Modify only the "enabled" field in the retrieved JSON
    JSON_PAYLOAD=$(
        echo "$CONFIG_JSON" | jq -r --argjson val "$status" '.enabled = $val'
    )

    # Check if jq successfully processed the JSON
    if [[ $? -ne 0 ]]; then
        log "ERROR: JSON parsing or modification failed using jq."
        return 1 # Indicate failure
    fi

    # 3. PUT the modified configuration back
    CURL_CODE=$(
        curl --compressed -s -o /dev/null -w "%{http_code}" \
             -X PUT "$ENDPOINT" \
             -H 'Content-Type: application/json' \
             --data-binary @- <<< "$JSON_PAYLOAD"
    )

    # Check for successful HTTP status codes (200 OK or 204 No Content)
    if [[ "$CURL_CODE" -eq 200 || "$CURL_CODE" -eq 204 ]]; then
        log "SUCCESS: Sent '$status' (HTTP $CURL_CODE)."
        return 0 # Indicate success
    else
        log "ERROR: PUT failed. HTTP $CURL_CODE received."
        return 1 # Indicate failure
    fi
}

# --- Main Logic ---

log "Starting Monitor (Interval: $((INTERVAL / 60)) min). Target: $ENDPOINT"
log "Enabling Hysteresis: Requires $SUCCESS_THRESHOLD consecutive checks."

# Initial check and loop starts
while true; do
    CURRENT_STATUS=$(check_internet)
    SHOULD_UPDATE=false
    API_STATUS="unknown"

    if [[ "$CURRENT_STATUS" == "true" ]]; then
        # Internet is UP. Increment the counter.
        CONSECUTIVE_SUCCESS_COUNT=$((CONSECUTIVE_SUCCESS_COUNT + 1))
        
        if [[ "$LAST_STATUS" == "false" ]] && [[ "$CONSECUTIVE_SUCCESS_COUNT" -ge "$SUCCESS_THRESHOLD" ]]; then
            # Hysteresis met: UP for N times and previously down. Time to enable.
            API_STATUS="true"
            SHOULD_UPDATE=true
            log "Connectivity stable ($CONSECUTIVE_SUCCESS_COUNT/$SUCCESS_THRESHOLD). Preparing to ENABLE endpoint."
        else
            # Not enough consecutive successes yet, or status hasn't changed from 'true'.
            log "Connectivity check success $CONSECUTIVE_SUCCESS_COUNT/$SUCCESS_THRESHOLD."
        fi

    elif [[ "$CURRENT_STATUS" == "false" ]]; then
        # Internet is DOWN. Reset counter immediately and disable if currently enabled.
        CONSECUTIVE_SUCCESS_COUNT=0
        
        if [[ "$LAST_STATUS" == "true" || "$LAST_STATUS" == "initial" ]]; then
            # Status changed from UP to DOWN. Time to disable immediately.
            API_STATUS="false"
            SHOULD_UPDATE=true
            log "Connectivity lost. Preparing to DISABLE endpoint immediately."
        else
            log "Connectivity still lost. Skipping curl."
        fi
    fi

    # Execute update if the logic above determined a status change is necessary
    if $SHOULD_UPDATE; then
        if update_endpoint "$API_STATUS"; then
            # ONLY update LAST_STATUS if the PUT request was successful
            LAST_STATUS="$API_STATUS"
        else
            # If update failed, log error. LAST_STATUS remains unchanged, 
            # ensuring a retry on the next interval.
            log "API update failed. Will retry next interval."
        fi
    fi

    sleep "$INTERVAL"
done
