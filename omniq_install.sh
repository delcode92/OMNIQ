#!/bin/bash

# omniq_install.sh - Install OmniQ client (Permission-friendly copy fix)
# Usage: bash omniq_install_permission_fix.sh

set -e  # Exit on any error

echo "=== OmniQ Client Installer ==="

# Configuration
DOWNLOAD_URL="https://github.com/delcode92/OMNIQ/releases/download/omniq/omniq-client.zip"
TEMP_DIR="/tmp/omniq_install"
ZIP_FILE="$TEMP_DIR/omniq-client.zip"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored output
print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}! $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

# Check if required tools are available
check_dependencies() {
  local missing_deps=()
  
  if ! command -v curl &> /dev/null; then
    missing_deps+=("curl")
  fi
  
  if ! command -v unzip &> /dev/null; then
    missing_deps+=("unzip")
  fi
  
  if ! command -v npm &> /dev/null; then
    missing_deps+=("npm")
  fi
  
  if [ ${#missing_deps[@]} -ne 0 ]; then
    print_error "Missing required dependencies: ${missing_deps[*]}"
    echo "Please install these dependencies and try again."
    exit 1
  fi
}

# Download the client
download_client() {
  print_warning "Downloading OmniQ client..."
  
  # Create temporary directory
  rm -rf "$TEMP_DIR"
  mkdir -p "$TEMP_DIR"
  
  # Download the zip file
  if ! curl -L -o "$ZIP_FILE" "$DOWNLOAD_URL"; then
    print_error "Failed to download client. Please check your internet connection and try again."
    exit 1
  fi
  
  if [ ! -f "$ZIP_FILE" ]; then
    print_error "Download failed - file not found"
    exit 1
  fi
  
  print_success "Download complete"
}

# Extract and install
install_client() {
  print_warning "Extracting package..."
  cd "$TEMP_DIR"
  if ! unzip -q "$ZIP_FILE"; then
    print_error "Failed to extract package. The zip file may be corrupted."
    exit 1
  fi
  
  # Check if package.json exists
  if [ ! -f "package.json" ]; then
    print_error "package.json not found after extraction"
    ls -la
    exit 1
  fi
  
  print_warning "Installing OmniQ globally..."
  
  # Get npm global directory
  local global_dir=$(npm config get prefix)
  local install_dir="$global_dir/lib/node_modules/omniq"
  
  echo "Installing to: $install_dir"
  echo "Binary directory: $global_dir/bin"
  
  # Try to remove existing installation (might fail if no permissions)
  rm -rf "$install_dir" 2>/dev/null || true
  
  # Try to create directory and copy files
  if mkdir -p "$install_dir" 2>/dev/null && cp -r . "$install_dir/" 2>/dev/null; then
    echo "Installed files to node_modules successfully"
  else
    # If that fails, try with sudo
    print_warning "Installing with sudo (may require password)..."
    sudo rm -rf "$install_dir" 2>/dev/null || true
    sudo mkdir -p "$install_dir"
    sudo cp -r . "$install_dir/"
  fi
  
  # Create symlink in bin directory
  local bin_dir="$global_dir/bin"
  rm -f "$bin_dir/omniq" 2>/dev/null || true
  if ln -s "$install_dir/bundle/gemini.js" "$bin_dir/omniq" 2>/dev/null; then
    echo "Created symlink successfully"
  else
    # If that fails, try with sudo
    print_warning "Creating symlink with sudo (may require password)..."
    sudo rm -f "$bin_dir/omniq" 2>/dev/null || true
    sudo ln -s "$install_dir/bundle/gemini.js" "$bin_dir/omniq"
  fi
  
  print_success "Installation successful"
}

# Cleanup
cleanup() {
  print_warning "Cleaning up..."
  cd /
  rm -rf "$TEMP_DIR"
}

# Main installation process
main() {
  echo ""
  echo "This script will download and install OmniQ client."
  echo ""
  
  # Auto-confirm for testing
  echo "Auto-confirming installation for testing..."
  
  check_dependencies
  download_client
  install_client
  cleanup
  
  echo ""
  print_success "=== Installation Complete ==="
  echo ""
  echo "OmniQ has been installed successfully!"
  echo ""
  echo "Usage:"
  echo "  omniq                    # Run OmniQ"
  echo ""
  echo "The server is already configured. Simply run 'omniq' to start using the client!"
  echo ""
  echo "Enjoy using OmniQ!"
}

# Run the installation
main "$@"
