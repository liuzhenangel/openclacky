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

@include lib/colors.sh
@include lib/os.sh
@include lib/shell.sh
@include lib/network.sh
@include lib/mise.sh
@include lib/gem.sh

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
