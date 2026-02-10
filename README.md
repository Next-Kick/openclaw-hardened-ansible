# OpenClaw Hardened Deployment (Ansible)

**Automated Tier 3+ Security Hardening for OpenClaw AI Agents**

This Ansible playbook implements and extends the security hardening measures described in the [OpenClaw Security Guide](https://nextkicklabs.substack.com/p/openclaw-hardened-deployment-security-with-ansible), providing a fully automated deployment with additional defense-in-depth layers.

## 🎯 What This Playbook Does

Deploys a **hardened OpenClaw installation** with:
- **Rootless Podman containers:** Strict isolation running as a non-privileged user.
- **Network egress filtering:** Squid proxy sidecar with a domain allowlist.
- **HTTPS termination:** Caddy reverse proxy with auto-generated self-signed certificates.
- **LiteLLM credential brokering:** OpenClaw never sees real API keys; LiteLLM spoofs models (e.g., Deepseek acting as Claude).
- **Consolidated Configuration:** Single `openclaw.json` master config for Gateway, Tools, and Agents.
- **Automated Identity:** EFF wordlist hostname generation and persistent SSH key management.
- **Multi-OS support:** Native tasks for **Arch Linux** and **Debian/Ubuntu** (AWS ready).
- **Security Monitoring:** Systemd-based weekly audits for prompt injections and blocked domains.

## 📊 Comparison: Article vs. This Implementation

| Feature | Original Article (Tier 3) | This Ansible Implementation |
|---------|---------------------------|------------------------------|
| **Container Runtime** | Docker | **Podman (rootless)** ⭐ |
| **Network Filtering** | Firewall only | **Firewall + Squid egress allowlist** ⭐ |
| **HTTPS** | Optional/Manual | **Caddy reverse proxy (Terminated HTTPS)** ⭐ |
| **Identity Management** | Manual setup | **Automated EFF wordlist generation** |
| **OS Support** | Ubuntu focus | **Arch + Debian/Ubuntu auto-detection** |
| **Deployment Method** | Manual | **Fully automated interactive script** |
| **Monitoring** | Manual cron | **Systemd timers + audit script** |
| **LLM Providers** | Anthropic focus | **Ollama (Deepseek) / Anthropic / OpenAI** |
| **Secrets Management** | Manual generation | **Auto-gen with PERSISTENCE across runs** ⭐ |
| **Access Control** | Token only | **Token + Manual Device Pairing** |

## 🚀 Major Enhancements Beyond the Article

### 1. **Persistent Secrets (No more Token Mismatch)** ⭐
The playbook now checks for an existing `OPENCLAW_GATEWAY_TOKEN` and `LITELLM_MASTER_KEY` on the host before generating new ones. Once you log in to the dashboard, your session remains valid even after redeploying the stack.

### 2. **Master Configuration (`openclaw.json`)**
We have moved away from multiple YAML files. A single, schema-validated `openclaw.json` controls:
- **Gateway:** Bindings, trusted proxies, and CORS origins.
- **Agents:** Two-agent setup (**FileSentry** for read-only, **Coder** for development).
- **Channels:** Global "Pairing" DM policy for Telegram, WhatsApp, etc.

### 3. **Squid Proxy for Egress Control**
**Not in the original guide.** Every outbound request from the OpenClaw container is inspected by a Squid proxy. 
- **Default allowed:** Google, GitHub, NPM, Telegram, Discord, Slack, etc.
- **Blocked:** Everything else. 
- **Update:** Use `./update-allowlist.sh` to add new domains at runtime without downtime.

### 4. **Caddy HTTPS Termination**
Fixes the "Secure Context" browser issues. Caddy serves the dashboard over HTTPS using a self-signed certificate mapped to your agent's unique name.

## 📋 Prerequisites

**Local Machine (Controller):**
- Ansible 2.10+
- OpenSSL (for cert generation)
- SSH Client (`ssh-keygen`)
- Python 3.8+

**Target Machine:**
- Arch Linux OR Debian/Ubuntu
- Initial root/sudo access (Password or AWS .pem key)
- 2GB+ RAM

## 🚀 Quick Start

### 1. Prepare
```bash
cd openclaw-hardened-ansible
chmod +x deploy.sh update-allowlist.sh
```

### 2. Deploy
Run the interactive script. It will prompt for your IP, provider, and keys.
```bash
./deploy.sh
```

**AWS/Cloud Example:**
```bash
./deploy.sh \
  --target 54.x.x.x \
  --ssh-user ubuntu \
  --ssh-key ~/my-aws-key.pem \
  --mgmt-cidr 192.168.20.0/24 \
  --provider ollama \
  --model "deepseek-r1:8b" \
  --url "http://10.100.1.25:11434"
```

### 3. Authenticate
Once finished, get your persistent token:
```bash
ssh -i ssh-keys/your-name.pem openclaw@IP "cat ~/openclaw-docker/.env | grep TOKEN"
```
Open **`https://IP:18789`**, click through the SSL warning, and paste the token in Settings.

### 4. Approve Device (Hardening Step 7)
Since device auth is enabled, you must approve your browser from the host CLI:
```bash
# Inside the OpenClaw host
podman exec openclaw-agent openclaw devices pending
podman exec openclaw-agent openclaw devices approve <YOUR_ID>
```

## 🔧 Maintenance

### Update Egress Allowlist
1. Edit `roles/tier3-setup/templates/allowlist.txt.j2`.
2. Run `./update-allowlist.sh -t IP --ssh-user USER --ask-pass`.

### Security Audits
A systemd timer runs `monitor-openclaw.sh` weekly. To run manually:
```bash
sudo /home/openclaw/openclaw-docker/monitor-openclaw.sh
```
Check the reports at `~/openclaw-docker/security-audit-YYYYMMDD.log`.

### Configuration Validation
If you see errors, run the OpenClaw "Doctor" to check the schema:
```bash
podman exec openclaw-agent openclaw doctor
```

## 📁 File Structure
- `deploy.sh`: Main entry point (interactive/CLI).
- `update-allowlist.sh`: Lightweight allowlist updater.
- `ssh-keys/`: Stores generated `.pem` and `.crt` files.
- `roles/tier3-setup/`: The core hardening logic.
- `requirements.yml`: Ansible dependencies (auto-installed).

## 📄 License
Provided as-is for harm-reduction. OpenClaw is architecturally "spicy"—this deployment reduces the blast radius but prompt injection remains an inherent risk of LLMs. Use burner accounts only.
