#!/usr/bin/env bash

# Game Server Management Script
# Manages game servers in the Docker containers directory

set -e

# Configuration
CONTAINERS_DIR="$HOME/git/dotfiles/modules/nixos/services/docker/containers"
GAME_SERVERS=("minecraft" "palworld" "enshrouded" "necesse")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_error() {
    echo -e "${RED}Error: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_info() {
    echo -e "${BLUE}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

# Show usage
show_usage() {
    cat << EOF
Game Server Manager

Usage:
    $(basename "$0")                          List all available game servers
    $(basename "$0") <game> status            Show status of game server
    $(basename "$0") <game> start             Start game server
    $(basename "$0") <game> stop              Stop game server
    $(basename "$0") <game> restart           Restart game server (full restart)
    $(basename "$0") <game> logs              Show game server logs
    $(basename "$0") <game> logs -f           Follow game server logs

Available games:
EOF
    for game in "${GAME_SERVERS[@]}"; do
        echo "    - $game"
    done
    echo ""
}

# List all game servers with their status
list_games() {
    print_info "=== Available Game Servers ==="
    echo ""

    for game in "${GAME_SERVERS[@]}"; do
        game_dir="$CONTAINERS_DIR/$game"

        if [ -d "$game_dir" ]; then
            # Check if docker-compose file exists
            if [ -f "$game_dir/docker-compose.yml" ] || [ -f "$game_dir/docker-compose.yaml" ]; then
                # Try to determine container status
                cd "$game_dir"
                if docker compose ps --format json 2>/dev/null | grep -q "running"; then
                    status="${GREEN}RUNNING${NC}"
                elif docker compose ps --format json 2>/dev/null | grep -q "exited"; then
                    status="${YELLOW}STOPPED${NC}"
                else
                    status="${YELLOW}NOT STARTED${NC}"
                fi
                echo -e "  ${BLUE}$game${NC} - $status"
            else
                echo -e "  ${BLUE}$game${NC} - ${YELLOW}NO COMPOSE FILE${NC}"
            fi
        else
            echo -e "  ${RED}$game${NC} - ${RED}DIRECTORY NOT FOUND${NC}"
        fi
    done
    echo ""
}

# Check if game exists
validate_game() {
    local game=$1
    local found=false

    for available_game in "${GAME_SERVERS[@]}"; do
        if [ "$available_game" = "$game" ]; then
            found=true
            break
        fi
    done

    if [ "$found" = false ]; then
        print_error "Unknown game: $game"
        echo ""
        echo "Available games: ${GAME_SERVERS[*]}"
        exit 1
    fi

    # Check if directory exists
    if [ ! -d "$CONTAINERS_DIR/$game" ]; then
        print_error "Game directory not found: $CONTAINERS_DIR/$game"
        exit 1
    fi

    # Check if compose file exists
    if [ ! -f "$CONTAINERS_DIR/$game/docker-compose.yml" ] && [ ! -f "$CONTAINERS_DIR/$game/docker-compose.yaml" ]; then
        print_error "No docker-compose file found for $game"
        exit 1
    fi
}

# Execute docker compose command
execute_compose() {
    local game=$1
    shift
    local args=("$@")

    cd "$CONTAINERS_DIR/$game"

    print_info "Executing: docker compose ${args[*]}"
    docker compose "${args[@]}"
}

# Show status
show_status() {
    local game=$1
    validate_game "$game"

    print_info "=== Status: $game ==="
    execute_compose "$game" ps
}

# Start game server
start_game() {
    local game=$1
    validate_game "$game"

    print_info "Starting $game server..."
    execute_compose "$game" up -d
    print_success "Successfully started $game server"
}

# Stop game server
stop_game() {
    local game=$1
    validate_game "$game"

    print_info "Stopping $game server..."
    execute_compose "$game" down
    print_success "Successfully stopped $game server"
}

# Restart game server
restart_game() {
    local game=$1
    validate_game "$game"

    print_info "Restarting $game server..."
    execute_compose "$game" down
    sleep 2
    execute_compose "$game" up -d
    print_success "Successfully restarted $game server"
}

# Show logs
show_logs() {
    local game=$1
    shift
    local args=("$@")
    validate_game "$game"

    print_info "=== Logs: $game ==="
    execute_compose "$game" logs "${args[@]}"
}

# Main script logic
main() {
    # No arguments - list games
    if [ $# -eq 0 ]; then
        list_games
        echo ""
        show_usage
        exit 0
    fi

    local game=$1
    local command=${2:-status}

    case "$command" in
        status)
            show_status "$game"
            ;;
        start)
            start_game "$game"
            ;;
        stop)
            stop_game "$game"
            ;;
        restart)
            restart_game "$game"
            ;;
        logs)
            shift 2
            show_logs "$game" "$@"
            ;;
        *)
            print_error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
