#!/bin/bash

# omniq_install.sh - Install OmniQ client
# Usage: curl -sL https://raw.githubusercontent.com/delcode92/OMNIQ/main/omniq_install.sh | bash

set -e  # Exit on any error

echo "=== OmniQ Client Installer ==="

# Configuration
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

# Fetch credentials from server
fetch_credentials() {
  # Try to fetch credentials from the server
  local server_url="http://145.223.20.135:3004"
  local response
  
  # Use curl to call the get_creds endpoint
  if response=$(curl -s -f "${server_url}/get_creds"); then
    # Check if the response indicates success
    if echo "$response" | grep -q '"success":true'; then
      # Extract credentials from response (the credentials object)
      local creds
      
      # Try to use jq if available
      if command -v jq &> /dev/null; then
        creds=$(echo "$response" | jq -c '.credentials' 2>/dev/null)
      else
        # Fallback extraction using sed for simple cases
        # This is a more robust fallback for extracting the credentials object
        creds=$(echo "$response" | sed -n 's/.*"credentials":\({[^}]*}\).*/\1/p')
        
        # If that didn't work, try another approach
        if [ -z "$creds" ]; then
          creds=$(echo "$response" | sed -n 's/.*"credentials":\({.*}\)},"reauthPerformed".*/\1/p')
        fi
      fi
      
      # Validate that we got credentials
      if [ -n "$creds" ] && [ "$creds" != "null" ]; then
        echo "$creds"
        return 0
      else
        return 1
      fi
    else
      return 1
    fi
  else
    return 1
  fi
}

# Save credentials to file
save_credentials() {
  local creds="$1"
  
  if [ -z "$creds" ]; then
    print_error "No credentials provided to save"
    return 1
  fi
  
  # Create .qwen directory if it doesn't exist
  local qwen_dir="$HOME/.qwen"
  if [ ! -d "$qwen_dir" ]; then
    print_warning "Creating $qwen_dir directory..."
    mkdir -p "$qwen_dir"
  fi
  
  # Write credentials to file (overwrite if exists)
  local creds_file="$qwen_dir/oauth_creds.json"
  print_warning "Saving credentials to $creds_file..."
  
  if echo "$creds" > "$creds_file"; then
    print_success "Credentials saved successfully"
    return 0
  else
    print_error "Failed to save credentials to $creds_file"
    return 1
  fi
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
  
  # Check for jq (optional, but preferred for JSON parsing)
  if ! command -v jq &> /dev/null; then
    print_warning "jq not found - will use fallback method for JSON parsing"
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
  # Get the global npm prefix
  local npm_prefix=$(npm config get prefix 2>/dev/null)
  local global_modules_dir="$npm_prefix/lib/node_modules"
  local omniq_dir="$global_modules_dir/omniq"
  
  # Try to create the global directory without sudo first
  if ! mkdir -p "$global_modules_dir" 2>/dev/null; then
    # If that fails, try with sudo
    print_warning "Creating global modules directory with sudo (may require password)..."
    sudo mkdir -p "$global_modules_dir"
  fi
  
  # Copy the omniq files to the global modules directory
  if ! rm -rf "$omniq_dir" 2>/dev/null || ! cp -r . "$omniq_dir" 2>/dev/null; then
    # If that fails, try with sudo
    sudo rm -rf "$omniq_dir"
    sudo cp -r . "$omniq_dir"
  fi
  
  # Create the symlink in the bin directory
  local bin_dir="$npm_prefix/bin"
  local omniq_bin="$bin_dir/omniq"
  local omniq_entry_point="$omniq_dir/bundle/gemini.js"
  
  if ! rm -f "$omniq_bin" 2>/dev/null || ! ln -s "$omniq_entry_point" "$omniq_bin" 2>/dev/null || ! chmod +x "$omniq_entry_point" 2>/dev/null; then
    # If that fails, try with sudo
    sudo rm -f "$omniq_bin"
    sudo ln -s "$omniq_entry_point" "$omniq_bin"
    sudo chmod +x "$omniq_entry_point"
  fi
  
  print_success "Installation successful"
  
  # Clean up the zip file
  rm -f "../$ASSET_NAME"
}

# Main installation process
main() {
  echo ""
  echo "This script will download and install OmniQ client."
  echo ""
  
  # Ask for confirmation
  # read -p "Do you want to continue? (y/N): " -n 1 -r
  # echo
  # if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  #   echo "Installation cancelled."
  #   exit 0
  # fi
  
  # Fetch and save credentials as the first step
  print_warning "Fetching credentials from server..."
  local creds
  if creds=$(fetch_credentials); then
    print_success "Credentials fetched successfully"
    if save_credentials "$creds"; then
      print_success "Credentials setup completed"
    else
      print_error "Failed to save credentials, continuing with installation..."
    fi
  else
    print_error "Failed to fetch credentials, continuing with installation..."
  fi
  
  check_dependencies
  
  echo "Creating temporary directory..."
  rm -rf "/tmp/omniq_temp"
  mkdir "/tmp/omniq_temp"
  cd "/tmp/omniq_temp"
  
  download_client
  install_client
  
  # Cleanup
  print_warning "Cleaning up..."
  cd /
  rm -rf "/tmp/omniq_temp" "/tmp/omniq-client.zip"
  
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