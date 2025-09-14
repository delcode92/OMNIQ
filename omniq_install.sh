#!/bin/bash

# omniq_install.sh - Install OmniQ client
# Usage: curl -sL https://raw.githubusercontent.com/delcode92/OMNIQ/main/omniq_install.sh | bash

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

# Fetch credentials from server
fetch_credentials() {
  print_warning "Fetching credentials from server..."
  
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
        print_success "Credentials fetched successfully"
        echo "$creds"
        return 0
      else
        print_error "Failed to extract credentials from server response"
        echo "Response was: $response"
        return 1
      fi
    else
      print_error "Server returned error: $response"
      return 1
    fi
  else
    print_error "Failed to connect to server at $server_url"
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
  
  # Check if package.json exists after extraction
  if [ ! -f "package.json" ]; then
    print_error "package.json not found after extraction"
    ls -la
    exit 1
  fi
  
  print_warning "Installing OmniQ globally..."
  # Try installing without sudo first
  if npm install -g . --ignore-scripts ; then
    print_success "Installation successful"
  else
    # If that fails, try with sudo
    print_warning "Installing with sudo (may require password)..."
    if sudo npm install -g . --ignore-scripts ; then
      print_success "Installation successful"
    else
      print_error "Installation failed"
      echo "Please check your npm permissions and try again."
      echo "You can also try: sudo npm install -g ."
      exit 1
    fi
  fi
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
  
  # Ask for confirmation
  # read -p "Do you want to continue? (y/N): " -n 1 -r
  # echo
  # if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  #   echo "Installation cancelled."
  #   exit 0
  # fi
  
  # Fetch and save credentials as the first step
  local creds
  if creds=$(fetch_credentials); then
    if save_credentials "$creds"; then
      print_success "Credentials setup completed"
    else
      print_error "Failed to save credentials, continuing with installation..."
    fi
  else
    print_error "Failed to fetch credentials, continuing with installation..."
  fi
  
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
