#!/bin/bash

# Server URL - using default from App.tsx
SERVER_URL="http://145.223.20.135:3004"

echo "=== Re-authentication Script ==="

# Remove existing client credential files (but not server credentials)
echo "Removing existing client credential files..."
rm -f ~/.qwen/oauth_creds.json
rm -f ~/.omn/omn_creds.json
rm -f ~/.omn/client.json

# Create directories if they don't exist
echo "Creating directories..."
mkdir -p ~/.qwen
mkdir -p ~/.omn

# Generate a new client ID
echo "Generating new client ID..."
CLIENT_ID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "client_$(date +%s)")

# Create client.json with the new client ID
echo "Creating client.json with client ID: $CLIENT_ID"
echo "{\"clientId\":\"$CLIENT_ID\"}" > ~/.omn/client.json

# Send client ID to server
echo "Registering client with server..."
RESPONSE=$(curl -s -w "\nHTTP_CODE:\n%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d "{\"clientId\":\"$CLIENT_ID\"}" \
  "$SERVER_URL/register_client")

# Split response into body and HTTP code
HTTP_CODE=$(echo "$RESPONSE" | awk '/HTTP_CODE:/ {getline; print}' | tr -d ' ')
RESPONSE_BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/,$d')

echo "Registration response - HTTP code: $HTTP_CODE"
# echo "Registration response body: $RESPONSE_BODY"

if [ "$HTTP_CODE" -eq 200 ]; then
  echo "✓ Client registered successfully"
else
  echo "✗ Failed to register client with server. HTTP code: $HTTP_CODE"
  echo "Response: $RESPONSE_BODY"
fi

# Fetch credentials from server
echo "Fetching credentials from server..."
CREDS_RESPONSE=$(curl -s -w "\nHTTP_CODE:\n%{http_code}" -X GET \
  -H "Content-Type: application/json" \
  "$SERVER_URL/get_creds")

# Split response into body and HTTP code
CREDS_HTTP_CODE=$(echo "$CREDS_RESPONSE" | awk '/HTTP_CODE:/ {getline; print}' | tr -d ' ')
CREDS_RESPONSE_BODY=$(echo "$CREDS_RESPONSE" | sed '/HTTP_CODE:/,$d')

echo "Credentials fetch - HTTP code: $CREDS_HTTP_CODE"
# echo "Credentials response body: $CREDS_RESPONSE_BODY"

if [ "$CREDS_HTTP_CODE" -eq 200 ]; then
  echo "✓ Credentials fetched successfully"
  
  # Save the response for debugging
  echo "$CREDS_RESPONSE_BODY" > /tmp/qwen_creds_response.json
  echo "Full response saved to /tmp/qwen_creds_response.json for debugging"
  
  # Check if the response contains valid credentials
  if echo "$CREDS_RESPONSE_BODY" | grep -q '"success":true'; then
    echo "✓ Server response indicates success"
    
    # Try to extract credentials if they exist in the response
    if echo "$CREDS_RESPONSE_BODY" | grep -q '"credentials"'; then
      echo "Found 'credentials' field in response"
      # Extract credentials using Python for proper JSON parsing
      CREDENTIALS=$(echo "$CREDS_RESPONSE_BODY" | python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    if 'credentials' in data and data['credentials']:
        json.dump(data['credentials'], sys.stdout, indent=2)
    else:
        print('{}')
except Exception as e:
    print('{}')
" 2>/dev/null)
      
      if [ "$CREDENTIALS" != "{}" ] && [ -n "$CREDENTIALS" ]; then
        echo "$CREDENTIALS" > ~/.omn/omn_creds.json
        echo "✓ Credentials saved to ~/.omn/omn_creds.json"
      else
        echo "⚠ Credentials field is empty"
        echo "{}" > ~/.omn/omn_creds.json
      fi
    else
      # If no credentials field, the response might be the credentials directly
      echo "No 'credentials' field found, using response directly"
      echo "$CREDS_RESPONSE_BODY" > ~/.omn/omn_creds.json
      echo "✓ Response saved to ~/.omn/omn_creds.json"
    fi
    
    # Create oauth_creds.json with the same credentials for compatibility
    echo "$CREDS_RESPONSE_BODY" | python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    if 'credentials' in data and data['credentials']:
        json.dump(data['credentials'], sys.stdout, indent=2)
    else:
        print('{}')
except Exception as e:
    print('{}')
" 2>/dev/null > ~/.qwen/oauth_creds.json
    echo "✓ Created ~/.qwen/oauth_creds.json with credentials"
    
    echo "✓ Re-authentication process completed successfully"
  else
    echo "✗ Server response indicates failure"
    echo "Response: $CREDS_RESPONSE_BODY"
    
    # Create empty credential files as fallback
    echo "{}" > ~/.omn/omn_creds.json
    echo "{}" > ~/.qwen/oauth_creds.json
    echo "⚠ Created empty credential files as fallback"
  fi
else
  echo "✗ Failed to fetch credentials from server. HTTP code: $CREDS_HTTP_CODE"
  echo "Response: $CREDS_RESPONSE_BODY"
  
  # Create empty credential files as fallback
  echo "{}" > ~/.omn/omn_creds.json
  echo "{}" > ~/.qwen/oauth_creds.json
  echo "⚠ Created empty credential files as fallback"
fi

echo "=== Re-authentication Script Completed ==="


