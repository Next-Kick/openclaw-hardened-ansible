#!/bin/bash
set -e

# Help Function
show_help() {
    echo "Usage: ./update-allowlist.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -t, --target IP       Target IP address (Required)"
    echo "  --ssh-user USER       SSH User (Default: root)"
    echo "  --ask-pass            Ask for SSH/Sudo passwords"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Description:"
    echo "  Updates the Squid allowlist on the remote host based on the local template"
    echo "  (roles/tier3-setup/templates/allowlist.txt.j2) and reloads the proxy."
}

TARGET_IP=""
SSH_USER="root"
ASK_PASS=false

# Parse Arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -t|--target) TARGET_IP="$2"; shift ;;
        --ssh-user) SSH_USER="$2"; shift ;;
        --ask-pass) ASK_PASS=true ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ -z "$TARGET_IP" ]; then
    echo "Error: Target IP is required."
    exit 1
fi

echo "🔄 Updating Allowlist on $TARGET_IP..."

# Create temporary inventory
TEMP_INVENTORY=$(mktemp)
echo "[openclaw_hosts]" > "$TEMP_INVENTORY"
echo "$TARGET_IP ansible_user=$SSH_USER" >> "$TEMP_INVENTORY"

# Check Local Dependencies
check_dep() {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: $1 is not installed locally. Please install it first."
        exit 1
    fi
}

check_dep ansible
check_dep ansible-playbook

# Install Ansible Requirements
echo "📦 Installing Ansible collections..."
ansible-galaxy collection install -r requirements.yml > /dev/null

# Ansible Args
ANSIBLE_ARGS=""
if [ "$ASK_PASS" = true ]; then
    ANSIBLE_ARGS="-k -K"
fi

# Run Playbook
ansible-playbook -i "$TEMP_INVENTORY" update-allowlist.yml $ANSIBLE_ARGS

# Cleanup
rm "$TEMP_INVENTORY"
echo "Done."
