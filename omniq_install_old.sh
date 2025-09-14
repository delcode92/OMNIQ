#!/bin/bash

# omniq_install.sh - Download and install OmniQ client
# Usage: curl -sL https://raw.githubusercontent.com/delcode92/OMNIQ/main/omniq_install.sh | bash

set -e  # Exit on any error

echo "=== OmniQ Client Installer ==="

# Configuration - Direct download link
DOWNLOAD_URL="https://github.com/delcode92/OMNIQ/releases/download/omniq/omniq-client.zip"
ASSET_NAME="omniq-client.zip"

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
  
  curl -L -o "$ASSET_NAME" "$DOWNLOAD_URL"
  
  if [ ! -f "$ASSET_NAME" ]; then
    print_error "Download failed"
    exit 1
  fi
  
  print_success "Download complete"
}

# Extract and install
install_client() {
  print_warning "Extracting package..."
  unzip -q "$ASSET_NAME"
  
  print_warning "Installing OmniQ globally..."
  if npm install -g . &>/dev/null; then
    print_success "Installation successful"
  else
    print_warning "Installing with sudo (may require password)..."
    if sudo npm install -g . &>/dev/null; then
      print_success "Installation successful"
    else
      print_error "Installation failed"
      echo "Please check your npm permissions and try again."
      exit 1
    fi
  fi
  
  print_warning "Cleaning up..."
  cd ..
  rm -rf "omniq_temp"
  rm "$ASSET_NAME"
}

# Main installation process
main() {
  echo ""
  echo "This script will download and install OmniQ client."
  echo ""
  
  # Ask for confirmation
  read -p "Do you want to continue? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
  fi
  
  check_dependencies
  
  echo "Creating temporary directory..."
  rm -rf "omniq_temp"
  mkdir "omniq_temp"
  cd "omniq_temp"
  
  download_client
  install_client
  
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
