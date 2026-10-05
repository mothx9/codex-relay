#!/bin/sh
# Per-user installation. No network, firewall, Wi-Fi, or VPN configuration changes.
set -eu
role=${1:-}
case "$role" in hub|agent) shift ;; *) printf '%s\n' 'Usage: install.sh hub|agent --public-url URL | --hub-url URL --machine ID --token-file FILE [--binary FILE] [--dry-run] [--no-start (Linux)]'; exit 2 ;; esac
relay_binary=''
hub_url=''
public_url=''
machine=''
token_file=''
codex_binary=''
insecure=''
dry_run=0
no_start=0
listen='127.0.0.1:8787'
while [ "$#" -gt 0 ]; do
 case "$1" in
  --binary) relay_binary=$2; shift 2 ;;
  --hub-url) hub_url=$2; shift 2 ;;
  --public-url) public_url=$2; shift 2 ;;
  --machine) machine=$2; shift 2 ;;
  --token-file) token_file=$2; shift 2 ;;
  --codex) codex_binary=$2; shift 2 ;;
  --listen) listen=$2; shift 2 ;;
  --insecure-http) insecure='--insecure-http'; shift ;;
  --dry-run) dry_run=1; shift ;;
  --no-start) no_start=1; shift ;;
  *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
 esac
done
os=$(uname -s)
arch=$(uname -m)
case "$os/$arch" in Linux/x86_64) target=linux-amd64 ;; Linux/aarch64|Linux/arm64) target=linux-arm64 ;; Darwin/arm64) target=darwin-arm64 ;; *) printf 'Unsupported target: %s/%s\n' "$os" "$arch" >&2; exit 1 ;; esac
if [ "$os" = Darwin ] && [ "$role" = hub ]; then printf '%s\n' 'Hub installation targets Linux; use the hub CLI directly on macOS.' >&2; exit 1; fi
if [ "$os" != Linux ] && [ "$no_start" = 1 ]; then printf '%s\n' '--no-start requires Linux/systemd; use --dry-run to prepare a macOS service definition.' >&2; exit 2; fi
# Documentation domains are not usable hub endpoints. Fail before installing files.
for endpoint in "$hub_url" "$public_url"; do
 [ -n "$endpoint" ] || continue
 case "$endpoint" in https://*|http://*) ;; *) printf '%s\n' 'The hub URL must be an actual http:// or https:// endpoint.' >&2; exit 2 ;; esac
 authority=${endpoint#*://}; authority=${authority%%/*}; hostname=${authority%%:*}
 hostname=$(printf '%s' "$hostname" | tr '[:upper:]' '[:lower:]')
 case "$hostname" in example.com|*.example.com|example.net|*.example.net|example.org|*.example.org|invalid|*.invalid)
  printf '%s\n' 'The hub URL is a documentation placeholder. Use the real HTTPS URL reported by your reverse proxy or Tailscale Serve.' >&2; exit 2 ;;
 esac
done
case "$role" in
 hub) [ -n "$public_url" ] || { printf '%s\n' '--public-url is required' >&2; exit 2; } ;;
 agent)
  [ -n "$hub_url" ] && [ -n "$machine" ] && [ -n "$token_file" ] || { printf '%s\n' '--hub-url, --machine, --token-file are required' >&2; exit 2; }
  case "$machine" in *[!A-Za-z0-9_-]*|'') printf '%s\n' 'Invalid machine ID' >&2; exit 2 ;; esac
  [ -f "$token_file" ] && [ -r "$token_file" ] && [ -s "$token_file" ] || {
   printf 'Agent token is missing, empty or unreadable: %s\n' "$token_file" >&2
   printf '%s\n' "Securely copy this machine's token from the active hub. If not yet enrolled, run codex-relay token add on that hub first. Cloning this repository does not enroll an agent; no service was installed." >&2
   exit 1
  }
  [ ! -L "$token_file" ] || { printf '%s\n' 'Token files must not be symlinks' >&2; exit 1; }
  if [ -z "$codex_binary" ]; then codex_binary=$(command -v codex || true); fi
  [ -n "$codex_binary" ] || { printf '%s\n' 'Install and sign in to Codex before installing an agent.' >&2; exit 1; } ;;
esac
install_bin="$HOME/.local/bin/codex-relay"
state_dir="$HOME/.local/share/codex-relay/$role"
config_dir="$HOME/.config/codex-relay"
case "$token_file" in /*|'') ;; *) token_file="$(pwd)/$token_file" ;; esac
# Reject newline-bearing values before writing either unit syntax.
for value in "$install_bin" "$state_dir" "$config_dir" "$public_url" "$hub_url" "$machine" "$token_file" "$codex_binary" "$listen" "$PATH"; do
 case "$value" in *'
'*) printf '%s\n' 'Newlines are not valid installation arguments' >&2; exit 2 ;; esac
done
if [ "$dry_run" = 0 ]; then
 umask 077
 mkdir -p "$(dirname "$install_bin")" "$state_dir" "$config_dir"
 if [ -z "$relay_binary" ]; then
  relay_version=${RELAY_VERSION:-v0.1.0-rc.2}
  download_dir=$(mktemp -d)
  trap 'rm -rf "$download_dir"' EXIT HUP INT TERM
  base="https://github.com/mothx9/codex-relay/releases/download/$relay_version"
  curl -fLSs "$base/codex-relay-$target" -o "$download_dir/codex-relay-$target"
  curl -fLSs "$base/SHA256SUMS" -o "$download_dir/SHA256SUMS"
  if command -v sha256sum >/dev/null 2>&1; then actual=$(sha256sum "$download_dir/codex-relay-$target" | awk '{print $1}'); else actual=$(shasum -a 256 "$download_dir/codex-relay-$target" | awk '{print $1}'); fi
  expected=$(awk -v file="codex-relay-$target" '$2==file {print $1}' "$download_dir/SHA256SUMS")
  [ -n "$expected" ] && [ "$actual" = "$expected" ] || { printf '%s\n' 'Binary checksum mismatch' >&2; exit 1; }
  relay_binary="$download_dir/codex-relay-$target"
 fi
 install -m 0755 "$relay_binary" "$install_bin"
 if [ "$role" = agent ]; then
  # Enrollment may already be staged at its final path.
  target_token="$config_dir/$machine.token"
  [ ! -L "$token_file" ] && [ ! -L "$target_token" ] || { printf '%s\n' 'Token files must not be symlinks' >&2; exit 1; }
  if [ "$token_file" -ef "$target_token" ]; then chmod 0600 "$target_token"
  else install -m 0600 "$token_file" "$target_token"; fi
 fi
fi
if [ "$role" = agent ]; then token_file="$config_dir/$machine.token"; fi
unit_quote() { printf '"'; printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/%/%%/g'; printf '"'; }
xml() { printf '%s' "$1" | sed 's/\&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'; }
if [ "$os" = Linux ]; then
 unit_dir="$HOME/.config/systemd/user"
 unit_file="$unit_dir/codex-relay-$role.service"
 render_unit() {
  printf '[Unit]\nDescription=Codex Relay %s\nStartLimitIntervalSec=0\n\n[Service]\nType=simple\nUMask=0077\nRestart=on-failure\nRestartSec=3\nTimeoutStopSec=15\nNoNewPrivileges=true\nWorkingDirectory=' "$role"
  printf '%s' "$state_dir" | sed 's/%/%%/g'; printf '\nEnvironment='; unit_quote "PATH=$PATH"; printf '\nExecStart='; unit_quote "$install_bin"; printf ' %s' "$role"
  if [ "$role" = hub ]; then printf ' --listen '; unit_quote "$listen"; printf ' --public-url '; unit_quote "$public_url"; printf ' --data-dir '; unit_quote "$state_dir"
  else printf ' --hub-url '; unit_quote "$hub_url"; printf ' --machine '; unit_quote "$machine"; printf ' --name '; unit_quote "$machine"; printf ' --token-file '; unit_quote "$token_file"; printf ' --codex '; unit_quote "$codex_binary"; fi
  [ -z "$insecure" ] || printf ' %s' "$insecure"
  printf '\n\n[Install]\nWantedBy=default.target\n'
 }
 if [ "$dry_run" = 1 ]; then render_unit; exit 0; fi
 mkdir -p "$unit_dir";render_unit > "$unit_file"
 systemctl --user daemon-reload
 if [ "$no_start" = 0 ]; then systemctl --user enable --now "codex-relay-$role.service"; fi
 printf 'Installed: %s\n' "$unit_file"
 if [ "$no_start" = 1 ]; then printf 'Service was not enabled or started. When the endpoint is ready: systemctl --user enable --now codex-relay-%s.service\n' "$role"; fi
 printf 'For operation after logout: sudo loginctl enable-linger "%s"\n' "$(id -un)"
else
 unit_dir="$HOME/Library/LaunchAgents";unit_file="$unit_dir/net.codex-relay.agent.plist"
 render_plist() {
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>Label</key><string>net.codex-relay.agent</string><key>ProgramArguments</key><array>'
  for value in "$install_bin" agent --hub-url "$hub_url" --machine "$machine" --name "$machine" --token-file "$token_file" --codex "$codex_binary"; do printf '<string>';xml "$value";printf '</string>';done
  [ -z "$insecure" ] || printf '<string>--insecure-http</string>'
  printf '</array><key>EnvironmentVariables</key><dict><key>PATH</key><string>';xml "$PATH";printf '</string></dict><key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>ThrottleInterval</key><integer>5</integer><key>WorkingDirectory</key><string>';xml "$state_dir";printf '</string><key>StandardOutPath</key><string>';xml "$state_dir/stdout.log";printf '</string><key>StandardErrorPath</key><string>';xml "$state_dir/stderr.log";printf '</string></dict></plist>\n'
 }
 if [ "$dry_run" = 1 ]; then render_plist; exit 0; fi
 mkdir -p "$unit_dir";render_plist > "$unit_file"
 launchctl bootout "gui/$(id -u)/net.codex-relay.agent" 2>/dev/null || true
 launchctl bootstrap "gui/$(id -u)" "$unit_file"
 printf 'Installed: %s\n' "$unit_file"
fi
