#!/bin/bash
# Connect to PostgreSQL container

set -e

# Load environment variables from .env if it exists
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# PostgreSQL connection settings (with defaults)
CONTAINER_NAME="${POSTGRES_CONTAINER:-eth-postgres}"
POSTGRES_DB="${POSTGRES_DB:-eth_indexer}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
POSTGRES_PORT="${POSTGRES_PORT:-5433}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print usage
print_usage() {
    echo -e "${BLUE}PostgreSQL Connection Script${NC}"
    echo ""
    echo "Usage: $0 [OPTIONS] [SQL_COMMAND]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -d, --docker        Connect via docker exec (default)"
    echo "  -l, --local         Connect via local psql client (requires psql installed)"
    echo "  -c, --command SQL   Execute SQL command and exit"
    echo ""
    echo "Environment variables (or from .env):"
    echo "  POSTGRES_DB         Database name (default: eth_indexer)"
    echo "  POSTGRES_USER       Database user (default: postgres)"
    echo "  POSTGRES_PASSWORD   Database password (default: postgres)"
    echo "  POSTGRES_PORT       Host port (default: 5433)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive session via docker"
    echo "  $0 -l                                 # Interactive session via local psql"
    echo "  $0 -c 'SELECT * FROM events LIMIT 5'  # Execute SQL command"
    echo "  $0 -l -c '\\dt'                        # List tables using local psql"
}

# Parse command line arguments
MODE="docker"
SQL_COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            print_usage
            exit 0
            ;;
        -d|--docker)
            MODE="docker"
            shift
            ;;
        -l|--local)
            MODE="local"
            shift
            ;;
        -c|--command)
            SQL_COMMAND="$2"
            shift 2
            ;;
        *)
            SQL_COMMAND="$1"
            shift
            ;;
    esac
done

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${RED}✗ PostgreSQL container '${CONTAINER_NAME}' is not running${NC}"
    echo -e "${YELLOW}Start it with: docker-compose up -d postgres${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Connecting to PostgreSQL...${NC}"
echo -e "${BLUE}  Container: ${CONTAINER_NAME}${NC}"
echo -e "${BLUE}  Database:  ${POSTGRES_DB}${NC}"
echo -e "${BLUE}  User:      ${POSTGRES_USER}${NC}"
echo ""

# Connect based on mode
if [ "$MODE" = "docker" ]; then
    # Connect via docker exec
    if [ -n "$SQL_COMMAND" ]; then
        # Execute SQL command (no -t flag for non-interactive)
        docker exec -i "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "$SQL_COMMAND"
    else
        # Interactive session
        echo -e "${YELLOW}Entering interactive psql session (type \\q to quit)${NC}"
        echo ""
        docker exec -it "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
    fi
elif [ "$MODE" = "local" ]; then
    # Check if psql is installed
    if ! command -v psql &> /dev/null; then
        echo -e "${RED}✗ psql command not found${NC}"
        echo -e "${YELLOW}Install PostgreSQL client or use docker mode: $0 -d${NC}"
        exit 1
    fi

    # Connect via local psql
    export PGPASSWORD="$POSTGRES_PASSWORD"
    if [ -n "$SQL_COMMAND" ]; then
        # Execute SQL command
        psql -h localhost -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "$SQL_COMMAND"
    else
        # Interactive session
        echo -e "${YELLOW}Entering interactive psql session (type \\q to quit)${NC}"
        echo ""
        psql -h localhost -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB"
    fi
    unset PGPASSWORD
fi
