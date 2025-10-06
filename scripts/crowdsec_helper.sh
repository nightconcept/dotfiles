#!/usr/bin/env bash
# CrowdSec Helper Script for Rinoa

REMOTE_HOST="rinoa"

show_usage() {
    cat << EOF
CrowdSec Helper Script

Usage: $0 <command>

Commands:
    status          - Show CrowdSec metrics and status
    bouncers        - List configured bouncers
    decisions       - Show current ban decisions
    ban <ip>        - Manually ban an IP address
    unban <ip>      - Manually unban an IP address
    logs            - Show CrowdSec logs (last 50 lines)
    bouncer-logs    - Show bouncer logs (last 50 lines)
    enroll          - Enroll with CrowdSec console
    restart         - Restart CrowdSec containers
    deploy          - Pull latest changes and rebuild on Rinoa

Examples:
    $0 status
    $0 ban 1.2.3.4
    $0 decisions
    $0 deploy
EOF
}

# Check if SSH connection works
check_connection() {
    if ! ssh -q "$REMOTE_HOST" exit; then
        echo "❌ Cannot connect to $REMOTE_HOST"
        exit 1
    fi
}

case "${1:-}" in
    status)
        check_connection
        echo "📊 CrowdSec Metrics:"
        ssh "$REMOTE_HOST" 'docker exec crowdsec cscli metrics'
        ;;

    bouncers)
        check_connection
        echo "🛡️  Configured Bouncers:"
        ssh "$REMOTE_HOST" 'docker exec crowdsec cscli bouncers list'
        ;;

    decisions)
        check_connection
        echo "🚫 Current Ban Decisions:"
        ssh "$REMOTE_HOST" 'docker exec crowdsec cscli decisions list'
        ;;

    ban)
        if [ -z "$2" ]; then
            echo "❌ Please provide an IP address to ban"
            echo "Usage: $0 ban <ip>"
            exit 1
        fi
        check_connection
        echo "🚫 Banning IP: $2"
        ssh "$REMOTE_HOST" "docker exec crowdsec cscli decisions add --ip $2 --duration 4h --reason 'manual ban'"
        ;;

    unban)
        if [ -z "$2" ]; then
            echo "❌ Please provide an IP address to unban"
            echo "Usage: $0 unban <ip>"
            exit 1
        fi
        check_connection
        echo "✅ Unbanning IP: $2"
        ssh "$REMOTE_HOST" "docker exec crowdsec cscli decisions delete --ip $2"
        ;;

    logs)
        check_connection
        echo "📋 CrowdSec Logs (last 50 lines):"
        ssh "$REMOTE_HOST" 'docker logs --tail 50 crowdsec'
        ;;

    bouncer-logs)
        check_connection
        echo "📋 Bouncer Logs (last 50 lines):"
        ssh "$REMOTE_HOST" 'docker logs --tail 50 crowdsec-bouncer-traefik'
        ;;

    enroll)
        check_connection
        echo "📝 Enrolling with CrowdSec Console..."
        ssh "$REMOTE_HOST" 'docker exec crowdsec cscli console enroll cmgflcoo8000u02kzs3bhju67'
        echo ""
        echo "✅ Enrollment request sent!"
        echo "👉 Approve at: https://app.crowdsec.net/"
        echo "👉 After approval, run: $0 restart"
        ;;

    restart)
        check_connection
        echo "🔄 Restarting CrowdSec containers..."
        ssh "$REMOTE_HOST" 'docker restart crowdsec crowdsec-bouncer-traefik'
        echo "✅ Containers restarted"
        ;;

    deploy)
        check_connection
        echo "🚀 Deploying to Rinoa..."
        ssh "$REMOTE_HOST" 'cd ~/git/dotfiles && git pull && flake-rebuild'
        echo "✅ Deployment complete"
        ;;

    *)
        show_usage
        exit 1
        ;;
esac
