#!/bin/bash
# Monitor eth-indexer indexing progress

API_URL="${API_URL:-http://localhost:8080}"
POLL_INTERVAL="${POLL_INTERVAL:-10}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Store previous state
declare -A prev_blocks
declare -A prev_timestamps

# Function to print header
print_header() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}ETH-Indexer Monitor${NC}"
    echo -e "${CYAN}API: ${API_URL}${NC}"
    echo -e "${CYAN}Poll Interval: ${POLL_INTERVAL}s${NC}"
    echo -e "${CYAN}================================${NC}"
    echo ""
}

# Function to fetch status
fetch_status() {
    curl -s "${API_URL}/status" 2>/dev/null
}

# Function to parse and display status
display_status() {
    local status_json="$1"
    local timestamp=$(date +%s)

    # Check if response is valid
    if [ -z "$status_json" ] || ! echo "$status_json" | jq empty 2>/dev/null; then
        echo -e "${RED}✗ Failed to fetch status from ${API_URL}/status${NC}"
        echo -e "${YELLOW}  Is the service running?${NC}"
        return 1
    fi

    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC}"
    echo ""

    # Parse event states
    local events=$(echo "$status_json" | jq -r '.events | keys[]' 2>/dev/null)

    if [ -z "$events" ]; then
        echo -e "${YELLOW}No events found in status response${NC}"
        return 1
    fi

    # Display each event state
    for event in $events; do
        local current_block=$(echo "$status_json" | jq -r ".events[\"$event\"].current_block // 0")
        local last_indexed=$(echo "$status_json" | jq -r ".events[\"$event\"].last_indexed_block // 0")
        local status_state=$(echo "$status_json" | jq -r ".events[\"$event\"].status // \"unknown\"")

        echo -e "${CYAN}Event: ${event}${NC}"
        echo -e "  Current Block:      ${GREEN}${current_block}${NC}"
        echo -e "  Last Indexed Block: ${GREEN}${last_indexed}${NC}"
        echo -e "  Status:             ${status_state}"

        # Calculate progress if we have previous data
        local key="${event}"
        if [ -n "${prev_blocks[$key]}" ]; then
            local prev_block=${prev_blocks[$key]}
            local prev_ts=${prev_timestamps[$key]}
            local blocks_indexed=$((last_indexed - prev_block))
            local time_elapsed=$((timestamp - prev_ts))

            if [ $time_elapsed -gt 0 ]; then
                local blocks_per_min=$(echo "scale=2; $blocks_indexed * 60 / $time_elapsed" | bc)

                if [ $blocks_indexed -gt 0 ]; then
                    echo -e "  Progress:           ${GREEN}+${blocks_indexed} blocks (${blocks_per_min} blocks/min)${NC}"
                elif [ $blocks_indexed -eq 0 ]; then
                    echo -e "  Progress:           ${YELLOW}No new blocks indexed${NC}"
                else
                    echo -e "  Progress:           ${RED}Negative progress (possible reorg)${NC}"
                fi
            fi
        fi

        # Update previous state
        prev_blocks[$key]=$last_indexed
        prev_timestamps[$key]=$timestamp

        echo ""
    done

    return 0
}

# Main monitoring loop
main() {
    print_header

    while true; do
        status=$(fetch_status)
        display_status "$status"

        if [ $? -eq 0 ]; then
            echo -e "${CYAN}Next update in ${POLL_INTERVAL}s... (Press Ctrl+C to stop)${NC}"
        else
            echo -e "${YELLOW}Retrying in ${POLL_INTERVAL}s...${NC}"
        fi

        echo ""
        sleep "$POLL_INTERVAL"
    done
}

# Check for required commands
for cmd in curl jq bc; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: Required command '$cmd' not found${NC}"
        echo -e "${YELLOW}Please install $cmd to use this script${NC}"
        exit 1
    fi
done

# Run main loop
main
