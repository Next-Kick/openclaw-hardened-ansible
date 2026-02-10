#!/bin/bash
set -e

# Help Function
show_help() {
    echo "Usage: ./deploy.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -t, --target IP       Target IP address"
    echo "  -p, --provider NAME   LLM Provider (ollama, anthropic, openai, etc.)"
    echo "  -m, --model NAME      Model Name (e.g., llama3, claude-3-5-sonnet-20240620)"
    echo "  -u, --url URL         API Base URL (e.g., http://10.0.110.1:11434)"
    echo "  -k, --key KEY         API Key"
    echo "  --ssh-user USER       Initial SSH User (Default: root for Arch, ubuntu for AWS Ubuntu)"
    echo "  --ssh-key PATH        Path to private key for SSH connection"
    echo "  --ask-pass            Ask for SSH and Sudo passwords"
    echo "  --non-interactive     Fail if missing arguments instead of prompting"
    echo "  -h, --help            Show this help message"
    echo ""
}

# Defaults
TARGET_IP=""
SSH_USER=""  # Will detect if empty, or default to root
LLM_PROVIDER=""
LLM_MODEL=""
LLM_URL=""
LLM_KEY=""
INTERACTIVE=true
ASK_PASS=false
SSH_KEY=""

# Parse Arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -t|--target) TARGET_IP="$2"; shift ;;
        -p|--provider) LLM_PROVIDER="$2"; shift ;;
        -m|--model) LLM_MODEL="$2"; shift ;;
        -u|--url) LLM_URL="$2"; shift ;;
        -k|--key) LLM_KEY="$2"; shift ;;
        --ssh-user) SSH_USER="$2"; shift ;;
        --ssh-key) SSH_KEY="$2"; shift ;;
        --ask-pass) ASK_PASS=true ;;
        --non-interactive) INTERACTIVE=false ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# --- Interactive Prompts ---

if [ "$INTERACTIVE" = true ]; then
    echo "=================================================="
    echo "   🛡️  OpenClaw Hardened Deployment Setup"
    echo "=================================================="
    echo ""

    # Target IP
    if [ -z "$TARGET_IP" ]; then
        read -p "Enter Target Host IP: " TARGET_IP
    fi

    # SSH User (Prompt if not set)
    if [ -z "$SSH_USER" ]; then
        echo "Enter Initial SSH User (e.g., 'root' for bare metal, 'ubuntu' for AWS, 'ec2-user'):"
        read -p "User [root]: " input_user
        SSH_USER="${input_user:-root}"
    fi

    # SSH Key (Prompt if not set)
    if [ -z "$SSH_KEY" ] && [ "$ASK_PASS" = false ]; then
        echo ""
        echo "Enter path to SSH Private Key (leave empty to use default/ssh-agent):"
        read -p "Key Path: " input_key
        SSH_KEY="${input_key}"
    fi

    # Provider
    if [ -z "$LLM_PROVIDER" ]; then
        echo ""
        echo "Select LLM Provider:"
        echo "  1) Ollama (Default)"
        echo "  2) Anthropic"
        echo "  3) OpenAI"
        echo "  4) Azure / Other OpenAI Compatible"
        read -p "Choice [1-4]: " provider_choice
        case $provider_choice in
            2) LLM_PROVIDER="anthropic" ;;
            3) LLM_PROVIDER="openai" ;;
            4) LLM_PROVIDER="openai_compatible" ;;
            *) LLM_PROVIDER="ollama" ;;
        esac
    fi

    # Model Name
    if [ -z "$LLM_MODEL" ]; then
        echo ""
        default_model=""
        if [ "$LLM_PROVIDER" == "ollama" ]; then default_model="llama3"; fi
        if [ "$LLM_PROVIDER" == "anthropic" ]; then default_model="claude-3-5-sonnet-20240620"; fi
        if [ "$LLM_PROVIDER" == "openai" ]; then default_model="gpt-4o"; fi
        
        read -p "Enter Model Name [$default_model]: " input_model
        LLM_MODEL="${input_model:-$default_model}"
    fi

    # Base URL (Conditional)
    if [ -z "$LLM_URL" ]; then
        if [ "$LLM_PROVIDER" == "ollama" ]; then
            echo ""
            read -p "Enter Ollama Base URL [http://10.0.110.1:11434]: " input_url
            LLM_URL="${input_url:-http://10.0.110.1:11434}"
        elif [ "$LLM_PROVIDER" == "openai_compatible" ]; then
             echo ""
             read -p "Enter API Base URL: " LLM_URL
        fi
    fi

    # API Key (Conditional)
    if [ -z "$LLM_KEY" ]; then
        if [ "$LLM_PROVIDER" != "ollama" ]; then
            echo ""
            read -s -p "Enter API Key: " LLM_KEY
            echo ""
        else
            LLM_KEY="ollama" 
        fi
    fi
fi

# --- Validation ---

if [ -z "$TARGET_IP" ]; then
    echo "Error: Target IP is required."
    exit 1
fi

if [ -z "$SSH_USER" ]; then SSH_USER="root"; fi # Default fallback
if [ -z "$LLM_PROVIDER" ]; then LLM_PROVIDER="ollama"; fi
if [ -z "$LLM_MODEL" ] && [ "$LLM_PROVIDER" == "ollama" ]; then LLM_MODEL="llama3"; fi
if [ -z "$LLM_URL" ] && [ "$LLM_PROVIDER" == "ollama" ]; then LLM_URL="http://10.0.110.1:11434"; fi
if [ -z "$LLM_KEY" ]; then LLM_KEY="sk-placeholder"; fi


# --- Execution ---

echo ""
echo "🚀 Deploying Configuration:"
echo "----------------------------------------"
echo "Target:    $TARGET_IP"
echo "User:      $SSH_USER"
if [ ! -z "$SSH_KEY" ]; then echo "SSH Key:   $SSH_KEY"; fi
echo "OS Check:  Auto-detect (Arch/Debian/Ubuntu)"
echo "Provider:  $LLM_PROVIDER"
echo "----------------------------------------"

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

check_dep openssl
check_dep ssh-keygen
check_dep ansible
check_dep ansible-playbook

# Check Wordlist
if [ ! -f "eff_large_wordlist.txt" ]; then
    echo "Error: eff_large_wordlist.txt not found. Please download it or run the setup command."
    exit 1
fi

# Install Ansible Requirements
echo "📦 Installing Ansible collections..."
ansible-galaxy collection install -r requirements.yml > /dev/null

# Run Ansible
ANSIBLE_ARGS=""
if [ "$ASK_PASS" = true ]; then
    ANSIBLE_ARGS="-k -K"
fi

if [ ! -z "$SSH_KEY" ]; then
    ANSIBLE_ARGS="$ANSIBLE_ARGS --private-key=$SSH_KEY"
fi

ansible-playbook -i "$TEMP_INVENTORY" playbook.yml $ANSIBLE_ARGS \
    --extra-vars "llm_provider='$LLM_PROVIDER' llm_model='$LLM_MODEL' llm_url='$LLM_URL' llm_key='$LLM_KEY'"

# Cleanup
rm "$TEMP_INVENTORY"

echo ""
echo "✅ Deployment finished."
