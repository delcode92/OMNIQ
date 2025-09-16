#!/usr/bin/env node
/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Hybrid Qwen CLI Server - HTTP + CLI Integration
 * Runs Qwen CLI normally while providing HTTP endpoints for external access
 */

import http from 'http';
import url from 'url';
import path from 'path';
import os from 'os';
import fs from 'fs';
import { watch } from 'fs';

// Simple in-memory store for conversation history
let conversationHistory = [];
let httpServer = null;
let credentialWatcher = null;
let qwenConfig = null;
let qwenClient = null;

console.log('=== Hybrid Qwen CLI Server ===');

// Get credential file path
const CREDENTIAL_FILE_PATH = path.join(os.homedir(), '.qwen', 'oauth_creds.json');

// Read current credentials
function readCredentials() {
  try {
    if (fs.existsSync(CREDENTIAL_FILE_PATH)) {
      const content = fs.readFileSync(CREDENTIAL_FILE_PATH, 'utf8');
      const creds = JSON.parse(content);
      
      // Check if expired
      if (creds.expiry_date) {
        const expiry = new Date(creds.expiry_date);
        const now = new Date();
        if (expiry < now) {
          return { valid: false, error: 'Credentials expired', credentials: creds };
        }
      }
      
      return { valid: true, credentials: creds };
    } else {
      return { valid: false, error: 'Credential file not found', credentials: null };
    }
  } catch (error) {
    return { valid: false, error: error.message, credentials: null };
  }
}

// Set up credential file monitoring
function setupCredentialMonitoring() {
  try {
    // Watch for file changes
    credentialWatcher = watch(CREDENTIAL_FILE_PATH, (eventType) => {
      if (eventType === 'change') {
        console.log('Credential file updated, will reload on next request');
        // The Qwen client should automatically pick up the new credentials
      }
    });
    
    credentialWatcher.on('error', (error) => {
      console.warn('Error watching credential file:', error.message);
    });
    
    console.log('✓ Credential monitoring enabled');
  } catch (error) {
    console.warn('Failed to set up credential monitoring:', error.message);
  }
}

// Process user input through Qwen CLI (real processing)
async function processUserInput(input) {
  // Add user message to history
  conversationHistory.push({ role: 'user', content: input });
  
  let response = '';
  
  try {
    // If we have a working Qwen config, use it
    if (qwenConfig && qwenConfig.getGeminiClient) {
      const geminiClient = qwenConfig.getGeminiClient();
      
      if (geminiClient && geminiClient.isInitialized && geminiClient.isInitialized()) {
        // Generate a prompt_id for this request
        const prompt_id = `server-${Date.now()}-${Math.random().toString(16).slice(2)}`;
        
        const chat = geminiClient.getChat();
        const apiResponse = await chat.sendMessage(
          {
            message: input
          },
          prompt_id
        );
        
        // Extract the response text
        if (apiResponse && apiResponse.candidates && apiResponse.candidates.length > 0) {
          const candidate = apiResponse.candidates[0];
          if (candidate.content && candidate.content.parts && candidate.content.parts.length > 0) {
            response = candidate.content.parts.map(part => part.text).join('');
          }
        }
      } else {
        response = `Qwen is initialized but not ready. Using fallback response for: ${input}`;
      }
    } else {
      // Fallback response
      response = `Qwen server response to: ${input}`;
    }
  } catch (error) {
    console.error('Error processing with Qwen:', error.message);
    response = `Error with Qwen processing: ${error.message}. Fallback response for: ${input}`;
  }
  
  // Add AI response to history
  conversationHistory.push({ role: 'assistant', content: response });
  
  return response;
}

// Manual re-authentication endpoint
async function reauthenticate() {
  console.log('Manual re-authentication requested');
  
  if (!qwenConfig) {
    console.error('Cannot re-authenticate: Config not initialized');
    return { success: false, error: 'Config not initialized' };
  }
  
  try {
    const settings = qwenConfig.getSettings ? qwenConfig.getSettings() : null;
    const selectedAuthType = settings?.merged?.selectedAuthType;
    
    if (selectedAuthType) {
      // Refresh auth with existing credentials
      await qwenConfig.refreshAuth(selectedAuthType);
      console.log('✓ Re-authentication successful');
      return { success: true, message: 'Re-authentication successful' };
    }
  } catch (error) {
    console.error('Re-authentication failed:', error.message);
    return { success: false, error: error.message };
  }
  
  return { success: false, error: 'No auth type selected' };
}

// Create HTTP server
const server = http.createServer(async (req, res) => {
  // Set CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  
  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }
  
  // Parse URL
  const parsedUrl = url.parse(req.url || '', true);
  const path = parsedUrl.pathname;
  
  // Health check endpoint
  if (req.method === 'GET' && path === '/health') {
    const creds = readCredentials();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ 
      status: 'ok',
      message: 'Hybrid Qwen CLI Server is running',
      version: '1.0.0',
      qwenReady: !!(qwenConfig && qwenConfig.getGeminiClient && qwenConfig.getGeminiClient().isInitialized && qwenConfig.getGeminiClient().isInitialized()),
      credentials: creds,
      credentialFile: CREDENTIAL_FILE_PATH
    }));
    return;
  }
  
  // Manual credential reload endpoint
  if (req.method === 'POST' && path === '/reauth') {
    try {
      const result = await reauthenticate();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(result));
    } catch (error) {
      console.error('Error during re-authentication:', error);
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Re-authentication error' }));
    }
    return;
  }
  
  // History endpoint
  if (req.method === 'GET' && path === '/history') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(conversationHistory));
    return;
  }
  
  // Get credentials endpoint
  if (req.method === 'GET' && path === '/get_creds') {
    try {
      // Check current credentials status
      const credsStatus = readCredentials();
      
      // If credentials are expired or invalid, run re-authentication
      if (!credsStatus.valid) {
        console.log('Credentials invalid or expired, running re-authentication');
        const reauthResult = await reauthenticate();
        
        // Check credentials again after re-auth
        const updatedCredsStatus = readCredentials();
        
        if (updatedCredsStatus.valid) {
          // Return the refreshed credentials
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ 
            success: true, 
            credentials: updatedCredsStatus.credentials,
            reauthPerformed: true,
            reauthResult: reauthResult
          }));
        } else {
          // Re-auth failed
          res.writeHead(401, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ 
            success: false, 
            error: 'Re-authentication failed',
            credentialsError: updatedCredsStatus.error,
            reauthResult: reauthResult
          }));
        }
      } else {
        // Credentials are valid, return them directly
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ 
          success: true, 
          credentials: credsStatus.credentials,
          reauthPerformed: false
        }));
      }
    } catch (error) {
      console.error('Error in get_creds endpoint:', error);
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ 
        success: false, 
        error: 'Internal server error while fetching credentials' 
      }));
    }
    return;
  }
  
  // Register client endpoint
  if (req.method === 'POST' && path === '/register_client') {
    let body = '';
    
    // Collect request body
    req.on('data', chunk => {
      body += chunk.toString();
    });
    
    // Process request
    req.on('end', async () => {
      try {
        const requestData = JSON.parse(body);
        const clientId = requestData.clientId;
        
        if (!clientId) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Missing clientId parameter' }));
          return;
        }
        
        // Log the client registration
        console.log(`Client registered with ID: ${clientId}`);
        
        // Send success response
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ 
          success: true, 
          message: 'Client registered successfully' 
        }));
      } catch (error) {
        console.error('Error processing client registration:', error);
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Internal server error' }));
      }
    });
    return;
  }
  
  // Main endpoint for processing queries
  if (req.method === 'POST' && path === '/query') {
    let body = '';
    
    // Collect request body
    req.on('data', chunk => {
      body += chunk.toString();
    });
    
    // Process request
    req.on('end', async () => {
      try {
        const requestData = JSON.parse(body);
        const userQuery = requestData.query;
        const stream = requestData.stream === true; // Check if streaming is requested
        
        if (!userQuery) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Missing query parameter' }));
          return;
        }
        
        // Process the query through Qwen CLI
        const response = await processUserInput(userQuery);
        
        if (stream) {
          // Handle streaming response
          res.writeHead(200, {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive'
          });
          
          // Simulate streaming by splitting response into chunks
          const words = response.split(' ');
          for (let i = 0; i < words.length; i++) {
            // Send each word with a small delay to simulate streaming
            await new Promise(resolve => setTimeout(resolve, 50));
            if (!res.writableEnded) {
              res.write(`data: ${JSON.stringify({ content: words[i] + (i < words.length - 1 ? ' ' : '') })}\n\n`);
            }
          }
          
          if (!res.writableEnded) {
            res.end();
          }
        } else {
          // Send regular JSON response
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ 
            query: userQuery,
            response: response,
            timestamp: new Date().toISOString()
          }));
        }
      } catch (error) {
        console.error('Error processing request:', error);
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Internal server error' }));
      }
    });
    return;
  }
  
  // 404 for all other routes
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not found' }));
});

// Start HTTP server
function startHttpServer() {
  const PORT = process.env.PORT ? parseInt(process.env.PORT) : 3004; // Use port 3004 instead
  
  server.listen(PORT, () => {
    console.log(`
=== Hybrid Qwen CLI Server Running ===`);
    console.log(`HTTP server listening on port ${PORT}`);
    console.log(`Health check: http://localhost:${PORT}/health`);
    console.log(`Send queries to: http://localhost:${PORT}/query`);
    console.log(`Re-authenticate: http://localhost:${PORT}/reauth`);
    console.log(`View history at: http://localhost:${PORT}/history`);
    console.log(`Monitoring credential file: ${CREDENTIAL_FILE_PATH}`);
    console.log(`=====================================
`);
  });
  
  // Graceful shutdown
  process.on('SIGINT', () => {
    console.log('Shutting down server...');
    if (credentialWatcher) {
      credentialWatcher.close();
    }
    server.close(() => {
      console.log('Server closed.');
      process.exit(0);
    });
  });
}

// Initialize and start hybrid server
async function startHybridServer() {
  console.log('Starting Hybrid Qwen CLI Server...');
  
  // Set up credential monitoring
  setupCredentialMonitoring();
  
  // Start HTTP server
  startHttpServer();
  
  // Import and initialize the Qwen CLI in non-interactive mode
  try {
    const { Config, AuthType, sessionId } = await import('@qwen-code/qwen-code-core');
    const { loadCliConfig } = await import('./packages/cli/dist/src/config/config.js');
    const { loadSettings } = await import('./packages/cli/dist/src/config/settings.js');
    const { loadExtensions } = await import('./packages/cli/dist/src/config/extension.js');
    const { validateAuthMethod } = await import('./packages/cli/dist/src/config/auth.js');
    
    // Load configuration
    const workspaceRoot = process.cwd();
    const settings = loadSettings(workspaceRoot);
    const extensions = loadExtensions(workspaceRoot);
    const argv = {}; // Empty argv for server mode
    
    // Create config
    qwenConfig = await loadCliConfig(
      settings.merged,
      extensions,
      sessionId,
      argv,
    );
    
    // Set noBrowser to true to prevent browser authentication
    qwenConfig.noBrowser = true;
    
    await qwenConfig.initialize();
    
    // Try to authenticate
    const selectedAuthType = settings.merged.selectedAuthType;
    if (selectedAuthType) {
      try {
        const err = validateAuthMethod(selectedAuthType);
        if (!err) {
          await qwenConfig.refreshAuth(selectedAuthType);
          console.log(`✓ Authenticated using ${selectedAuthType}`);
        } else {
          console.warn('Auth validation failed:', err);
        }
      } catch (authError) {
        console.warn('Authentication failed:', authError.message);
      }
    }
    
    console.log('✓ Qwen CLI initialized in non-interactive mode');
  } catch (error) {
    console.error('Failed to initialize Qwen CLI:', error.message);
  }
}

// Start the hybrid server
startHybridServer().catch(error => {
  console.error('Failed to start hybrid server:', error);
  process.exit(1);
});

// Export for testing
export { server, processUserInput, reauthenticate, setupCredentialMonitoring };

