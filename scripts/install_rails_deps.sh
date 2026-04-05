#!/bin/bash
# install_rails_deps.sh — install Ruby 3.3+ and Node.js 22+ via mise for Rails development
# Generated from scripts/build/src/install_rails_deps.sh.cc — DO NOT EDIT DIRECTLY
#
# Usage:
#   bash install_rails_deps.sh            # install ruby + node
#   bash install_rails_deps.sh ruby       # install ruby only
#   bash install_rails_deps.sh node       # install node only

set -e

INSTALL_TARGET="${1:-all}"  # all | ruby | node


# ---[ @include lib/colors.sh ]---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1"; }
print_step()    { echo -e "\n${BLUE}==>${NC} $1"; }


# ---[ @include lib/os.sh ]---

# Sets OS (macOS | Linux | Windows | Unknown) and DISTRO (ubuntu | debian | …)
detect_os() {
    case "$(uname -s)" in
        Linux*)  OS=Linux  ;;
        Darwin*) OS=macOS  ;;
        CYGWIN*) OS=Windows ;;
        MINGW*)  OS=Windows ;;
        *)       OS=Unknown ;;
    esac
    print_info "Detected OS: $OS"

    if [ "$OS" = "Linux" ] && [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        DISTRO=$ID
        print_info "Detected Linux distribution: $DISTRO"
    else
        DISTRO=unknown
    fi
}

# Returns 0 if the given command is on PATH
command_exists() { command -v "$1" >/dev/null 2>&1; }

# Boolean helpers — use these in business logic instead of inline string comparisons
is_macos()     { [ "$OS" = "macOS" ]; }
is_linux_apt() { [ "$OS" = "Linux" ] && { [ "$DISTRO" = "ubuntu" ] || [ "$DISTRO" = "debian" ]; }; }

# Returns 0 (true) if $1 >= $2  (semantic version comparison)
version_ge() { printf '%s\n%s\n' "$2" "$1" | sort -V -C; }

# Assert that the current OS/distro is supported (macOS or Ubuntu/Debian).
# Optional $1: hint message printed on failure (e.g. manual install instructions).
# Exits with code 1 on unsupported OS or distro.
assert_supported_os() {
    local hint="${1:-}"
    if [ "$OS" = "Linux" ]; then
        if [ "$DISTRO" = "ubuntu" ] || [ "$DISTRO" = "debian" ]; then
            return 0
        fi
        print_error "Unsupported Linux distribution: $DISTRO"
        [ -n "$hint" ] && print_info "$hint"
        exit 1
    elif [ "$OS" = "macOS" ]; then
        return 0
    else
        print_error "Unsupported OS: $OS"
        [ -n "$hint" ] && print_info "$hint"
        exit 1
    fi
}


# ---[ @include lib/shell.sh ]---

# Sets CURRENT_SHELL (zsh | bash | fish) and SHELL_RC (path to rc file)
detect_shell() {
    local shell_name
    shell_name=$(basename "$SHELL")

    case "$shell_name" in
        zsh)
            CURRENT_SHELL="zsh"
            SHELL_RC="$HOME/.zshrc"
            ;;
        fish)
            CURRENT_SHELL="fish"
            SHELL_RC="$HOME/.config/fish/config.fish"
            ;;
        bash)
            CURRENT_SHELL="bash"
            # macOS uses ~/.bash_profile; Linux uses ~/.bashrc
            if is_macos; then
                SHELL_RC="$HOME/.bash_profile"
            else
                SHELL_RC="$HOME/.bashrc"
            fi
            ;;
        *)
            CURRENT_SHELL="bash"
            SHELL_RC="$HOME/.bashrc"
            ;;
    esac

    print_info "Detected shell: $CURRENT_SHELL (rc file: $SHELL_RC)"
}


# ---[ @include lib/network.sh ]---

# --------------------------------------------------------------------------
# Mirror variables — overridden by detect_network_region()
# --------------------------------------------------------------------------
SLOW_THRESHOLD_MS=5000
NETWORK_REGION="global"   # china | global | unknown
USE_CN_MIRRORS=false

GITHUB_RAW_BASE_URL="https://raw.githubusercontent.com"
DEFAULT_RUBYGEMS_URL="https://rubygems.org"
DEFAULT_NPM_REGISTRY="https://registry.npmjs.org"
DEFAULT_MISE_INSTALL_URL="https://mise.run"

CN_CDN_BASE_URL="https://oss.1024code.com"
CN_MISE_INSTALL_URL="${CN_CDN_BASE_URL}/mise.sh"
CN_RUBY_PRECOMPILED_URL="${CN_CDN_BASE_URL}/ruby/ruby-{version}.{platform}.tar.gz"
CN_RUBYGEMS_URL="https://mirrors.aliyun.com/rubygems/"
CN_NPM_REGISTRY="https://registry.npmmirror.com"
CN_NODE_MIRROR_URL="https://cdn.npmmirror.com/binaries/node/"
CN_GEM_BASE_URL="${CN_CDN_BASE_URL}/openclacky"
CN_GEM_LATEST_URL="${CN_GEM_BASE_URL}/latest.txt"

# Active values (set by detect_network_region)
MISE_INSTALL_URL="$DEFAULT_MISE_INSTALL_URL"
RUBYGEMS_INSTALL_URL="$DEFAULT_RUBYGEMS_URL"
NPM_REGISTRY_URL="$DEFAULT_NPM_REGISTRY"
NODE_MIRROR_URL=""          # empty = mise default (nodejs.org)
RUBY_VERSION_SPEC="ruby@3"  # CN mode pins to a specific precompiled build

# --------------------------------------------------------------------------
# Internal probe helpers
# --------------------------------------------------------------------------

# Probe a single URL; echoes round-trip time in ms, or "timeout"
_probe_url() {
    local url="$1"
    local out http_code total_time
    out=$(curl -s -o /dev/null -w "%{http_code} %{time_total}" \
        --connect-timeout 5 --max-time 5 "$url" 2>/dev/null) || true
    http_code="${out%% *}"
    total_time="${out#* }"
    if [ -z "$http_code" ] || [ "$http_code" = "000" ] || [ "$http_code" = "$out" ]; then
        echo "timeout"; return
    fi
    awk -v s="$total_time" 'BEGIN { printf "%d", s * 1000 }'
}

# Returns 0 (true) if result is slow or unreachable
_is_slow_or_unreachable() {
    local r="$1"
    [ "$r" = "timeout" ] && return 0
    [ "${r:-9999}" -ge "$SLOW_THRESHOLD_MS" ] 2>/dev/null
}

_format_probe_time() {
    local r="$1"
    [ "$r" = "timeout" ] && echo "timeout" && return
    awk -v ms="$r" 'BEGIN { printf "%.1fs", ms / 1000 }'
}

_print_probe_result() {
    local label="$1" result="$2"
    if [ "$result" = "timeout" ]; then
        print_warning "UNREACHABLE  ${label}"
    elif _is_slow_or_unreachable "$result"; then
        print_warning "SLOW ($(_format_probe_time "$result"))  ${label}"
    else
        print_success "OK ($(_format_probe_time "$result"))  ${label}"
    fi
}

# Probe URL up to max_retries times; returns first fast result or last result
_probe_url_with_retry() {
    local url="$1" max="${2:-2}" result
    for _ in $(seq 1 "$max"); do
        result=$(_probe_url "$url")
        ! _is_slow_or_unreachable "$result" && { echo "$result"; return 0; }
    done
    echo "$result"
}

# --------------------------------------------------------------------------
# detect_network_region — sets USE_CN_MIRRORS and active mirror variables
# --------------------------------------------------------------------------
detect_network_region() {
    print_step "Network pre-flight check..."
    echo ""

    local google_result baidu_result
    google_result=$(_probe_url "https://www.google.com")
    baidu_result=$(_probe_url "https://www.baidu.com")

    _print_probe_result "google.com" "$google_result"
    _print_probe_result "baidu.com"  "$baidu_result"

    local google_ok=false baidu_ok=false
    ! _is_slow_or_unreachable "$google_result" && google_ok=true
    ! _is_slow_or_unreachable "$baidu_result"  && baidu_ok=true

    if [ "$google_ok" = true ]; then
        NETWORK_REGION="global"
        print_success "Region: global"
    elif [ "$baidu_ok" = true ]; then
        NETWORK_REGION="china"
        print_success "Region: china"
    else
        NETWORK_REGION="unknown"
        print_warning "Region: unknown (both unreachable)"
    fi
    echo ""

    if [ "$NETWORK_REGION" = "china" ]; then
        local cdn_result mirror_result
        cdn_result=$(_probe_url_with_retry "$CN_MISE_INSTALL_URL")
        mirror_result=$(_probe_url_with_retry "$CN_RUBYGEMS_URL")

        _print_probe_result "CN CDN (mise/Ruby)" "$cdn_result"
        _print_probe_result "Aliyun (gem)"       "$mirror_result"

        local cdn_ok=false mirror_ok=false
        ! _is_slow_or_unreachable "$cdn_result"    && cdn_ok=true
        ! _is_slow_or_unreachable "$mirror_result" && mirror_ok=true

        if [ "$cdn_ok" = true ] || [ "$mirror_ok" = true ]; then
            USE_CN_MIRRORS=true
            MISE_INSTALL_URL="$CN_MISE_INSTALL_URL"
            RUBYGEMS_INSTALL_URL="$CN_RUBYGEMS_URL"
            NPM_REGISTRY_URL="$CN_NPM_REGISTRY"
            NODE_MIRROR_URL="$CN_NODE_MIRROR_URL"
            RUBY_VERSION_SPEC="ruby@3.4.8"
            print_info "CN mirrors applied"
        else
            print_warning "CN mirrors unreachable — falling back to global sources"
        fi
    else
        local rubygems_result mise_result
        rubygems_result=$(_probe_url_with_retry "$DEFAULT_RUBYGEMS_URL")
        mise_result=$(_probe_url_with_retry "$DEFAULT_MISE_INSTALL_URL")

        _print_probe_result "RubyGems" "$rubygems_result"
        _print_probe_result "mise.run" "$mise_result"

        _is_slow_or_unreachable "$rubygems_result" && print_warning "RubyGems is slow/unreachable."
        _is_slow_or_unreachable "$mise_result"     && print_warning "mise.run is slow/unreachable."

        USE_CN_MIRRORS=false
        RUBY_VERSION_SPEC="ruby@3"
    fi

    echo ""
}


# ---[ @include lib/mise.sh ]---

# --------------------------------------------------------------------------
# Internal helper — locate the mise binary
# --------------------------------------------------------------------------
_mise_bin() {
    if [ -x "$HOME/.local/bin/mise" ]; then
        echo "$HOME/.local/bin/mise"
    elif command_exists mise; then
        command -v mise
    else
        echo ""
    fi
}

# --------------------------------------------------------------------------
# ensure_mise — install mise if missing, activate it in the current session
# --------------------------------------------------------------------------
ensure_mise() {
    local mise
    mise=$(_mise_bin)

    if [ -n "$mise" ]; then
        print_success "mise already installed: $($mise --version 2>/dev/null || echo 'n/a')"
        export PATH="$HOME/.local/bin:$PATH"
        eval "$($mise activate bash 2>/dev/null)" 2>/dev/null || true
        MISE_BIN="$mise"
        return 0
    fi

    print_step "Installing mise..."
    if curl -fsSL "$MISE_INSTALL_URL" | sh; then
        export PATH="$HOME/.local/bin:$PATH"
        eval "$(~/.local/bin/mise activate bash 2>/dev/null)" 2>/dev/null || true

        # Persist mise activation to shell rc
        local init_line='eval "$(~/.local/bin/mise activate '"$CURRENT_SHELL"')"'
        if ! grep -q "mise activate" "$SHELL_RC" 2>/dev/null; then
            echo "$init_line" >> "$SHELL_RC"
            print_info "Added mise activation to $SHELL_RC"
        fi

        MISE_BIN="$HOME/.local/bin/mise"
        print_success "mise installed"
    else
        print_error "Failed to install mise"
        return 1
    fi
}

# --------------------------------------------------------------------------
# install_ruby_via_mise — install Ruby via mise
#   CN mode: precompiled binary from oss.1024code.com
#   Global:  mise default (precompiled where available)
# --------------------------------------------------------------------------
install_ruby_via_mise() {
    local mise="${MISE_BIN:-$(_mise_bin)}"
    if [ -z "$mise" ]; then
        print_error "mise not found — call ensure_mise first"
        return 1
    fi

    print_info "Installing Ruby via mise ($RUBY_VERSION_SPEC)..."

    if [ "$USE_CN_MIRRORS" = true ]; then
        "$mise" settings ruby.compile=false 2>/dev/null || true
        "$mise" settings ruby.precompiled_url="$CN_RUBY_PRECOMPILED_URL" 2>/dev/null || true
        print_info "Using precompiled Ruby from CN CDN"
    else
        # Enable precompiled binaries globally (mise supports this on common platforms)
        "$mise" settings ruby.compile=false 2>/dev/null || true
        "$mise" settings unset ruby.precompiled_url 2>/dev/null || true
    fi

    if "$mise" use -g "$RUBY_VERSION_SPEC"; then
        eval "$($mise activate bash 2>/dev/null)" 2>/dev/null || true
        local installed
        installed=$(ruby -e 'puts RUBY_VERSION' 2>/dev/null || echo "unknown")
        print_success "Ruby $installed installed"
    else
        print_error "Failed to install Ruby via mise"
        return 1
    fi
}

# --------------------------------------------------------------------------
# install_node_via_mise — install Node.js 22 via mise
# --------------------------------------------------------------------------
install_node_via_mise() {
    local mise="${MISE_BIN:-$(_mise_bin)}"
    if [ -z "$mise" ]; then
        print_error "mise not found — call ensure_mise first"
        return 1
    fi

    # Skip if compatible Node is already active
    if command_exists node; then
        local ver major
        ver=$(node --version 2>/dev/null | sed 's/v//')
        major="${ver%%.*}"
        if [ "${major:-0}" -ge 22 ] 2>/dev/null; then
            print_success "Node.js v${ver} already satisfies >= 22 — skipping"
            return 0
        fi
    fi

    # Apply CN Node mirror if needed
    if [ "$USE_CN_MIRRORS" = true ] && [ -n "$NODE_MIRROR_URL" ]; then
        "$mise" settings node.mirror_url="$NODE_MIRROR_URL" 2>/dev/null || true
        print_info "Node mirror → ${NODE_MIRROR_URL}"
    fi

    print_info "Installing Node.js 22 via mise..."
    if "$mise" use -g node@22; then
        eval "$($mise activate bash 2>/dev/null)" 2>/dev/null || true
        print_success "Node.js $(node --version 2>/dev/null) installed"
    else
        print_error "Failed to install Node.js via mise"
        return 1
    fi
}


# ---[ @include lib/gem.sh ]---

configure_gem_source() {
    local gemrc="$HOME/.gemrc"

    if [ "$USE_CN_MIRRORS" = true ]; then
        if grep -q "${CN_RUBYGEMS_URL}" "$gemrc" 2>/dev/null; then
            print_success "gem source already → ${CN_RUBYGEMS_URL}"
        else
            [ -f "$gemrc" ] && mv "$gemrc" "$HOME/.gemrc_clackybak"
            cat > "$gemrc" <<GEMRC
:sources:
  - ${CN_RUBYGEMS_URL}
GEMRC
            print_success "gem source → ${CN_RUBYGEMS_URL}"
        fi
    else
        if [ -f "$gemrc" ] && grep -q "${CN_RUBYGEMS_URL}" "$gemrc" 2>/dev/null; then
            if [ -f "$HOME/.gemrc_clackybak" ]; then
                mv "$HOME/.gemrc_clackybak" "$gemrc"
                print_info "gem source restored from backup"
            else
                rm "$gemrc"
                print_info "gem source restored to default"
            fi
        fi
    fi
}

restore_gemrc() {
    local gemrc="$HOME/.gemrc"
    local gemrc_bak="$HOME/.gemrc_clackybak"
    if [ -f "$gemrc_bak" ]; then
        mv "$gemrc_bak" "$gemrc"
        print_success "~/.gemrc restored from backup"
    elif [ -f "$gemrc" ]; then
        rm "$gemrc"
        print_success "~/.gemrc removed"
    else
        print_info "~/.gemrc — nothing to restore"
    fi
}

# --------------------------------------------------------------------------
# Redirect GEM_HOME to user dir when system Ruby gem dir is not writable
# --------------------------------------------------------------------------
setup_gem_home() {
    local gem_dir
    gem_dir=$(gem environment gemdir 2>/dev/null || true)
    [ -w "$gem_dir" ] && return 0

    local ruby_api
    ruby_api=$(ruby -e 'puts RbConfig::CONFIG["ruby_version"]' 2>/dev/null)
    export GEM_HOME="$HOME/.gem/ruby/${ruby_api}"
    export GEM_PATH="$HOME/.gem/ruby/${ruby_api}"
    export PATH="$HOME/.gem/ruby/${ruby_api}/bin:$PATH"
    print_info "System Ruby detected — gems will install to ~/.gem/ruby/${ruby_api}"

    if [ -n "$SHELL_RC" ] && ! grep -q "GEM_HOME" "$SHELL_RC" 2>/dev/null; then
        {
            echo ""
            echo "# Ruby user gem dir (added by openclacky installer)"
            echo "export GEM_HOME=\"\$HOME/.gem/ruby/${ruby_api}\""
            echo "export GEM_PATH=\"\$HOME/.gem/ruby/${ruby_api}\""
            echo "export PATH=\"\$HOME/.gem/ruby/${ruby_api}/bin:\$PATH\""
        } >> "$SHELL_RC"
        print_info "GEM_HOME written to $SHELL_RC"
    fi
}

restore_gem_home() {
    [ -n "$SHELL_RC" ] && [ -f "$SHELL_RC" ] || return 0
    grep -q "GEM_HOME" "$SHELL_RC" 2>/dev/null || return 0
    # Remove the block written by setup_gem_home (comment + 3 export lines)
    local tmp
    tmp=$(mktemp)
    grep -v "# Ruby user gem dir (added by openclacky installer)" "$SHELL_RC" \
        | grep -v "export GEM_HOME=" \
        | grep -v "export GEM_PATH=" \
        | grep -v "/.gem/ruby/" \
        > "$tmp" && mv "$tmp" "$SHELL_RC"
    print_success "GEM_HOME removed from $SHELL_RC"
}


# --------------------------------------------------------------------------
# Ruby: install via mise and configure gem source
# --------------------------------------------------------------------------
install_ruby() {
    print_step "Installing Ruby via mise..."

    ensure_mise || return 1
    install_ruby_via_mise || return 1

    # Configure gem source for CN users
    configure_gem_source

    # Reinstall openclacky in the new Ruby environment
    "${MISE_BIN:-mise}" exec -- gem install openclacky --no-document \
        && print_success "openclacky reinstalled" \
        || print_warning "Could not reinstall openclacky — run manually: gem install openclacky --no-document"
}

# --------------------------------------------------------------------------
# Node: install via mise and configure npm registry
# --------------------------------------------------------------------------
install_node() {
    print_step "Installing Node.js via mise..."

    ensure_mise || return 1
    install_node_via_mise || return 1

    if [ "$USE_CN_MIRRORS" = true ] && command_exists npm; then
        npm config set registry "$NPM_REGISTRY_URL" 2>/dev/null || true
        print_info "npm registry → ${NPM_REGISTRY_URL}"
    fi
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║   🔧 Rails Dependencies Installer                        ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""

    detect_shell
    detect_network_region

    # Run system deps script if available
    local sys_deps="$HOME/.clacky/scripts/install_system_deps.sh"
    [ -f "$sys_deps" ] && { bash "$sys_deps" || print_warning "System deps install had warnings — continuing"; }

    case "$INSTALL_TARGET" in
        ruby) install_ruby || exit 1 ;;
        node) install_node || exit 1 ;;
        *)
            install_ruby || exit 1
            install_node || exit 1
            ;;
    esac

    echo ""
    print_success "Done. Please re-source your shell or open a new terminal if paths changed."
    echo ""
}

main "$@"
