#!/usr/bin/env bun

import { writeFile } from 'fs/promises';
import { existsSync, readFileSync } from 'fs';

// Module constants
const OAUTH_TOKEN_URL = 'https://console.anthropic.com/v1/oauth/token';
const CLIENT_ID = '9d1c250a-e61b-44d9-88ed-5944d1962f5e';

// Types
interface ClaudeOAuthData {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
  scopes: string[];
  isMax: boolean;
}

interface Credentials {
  claudeAiOauth: ClaudeOAuthData;
}

interface TokenRefreshResponse {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  scope?: string;
}

function loadCredentials(credentialsPath: string): Credentials | null {
  if (!existsSync(credentialsPath)) {
    console.log(`❌ Credentials file not found: ${credentialsPath}`);
    return null;
  }

  try {
    const content = readFileSync(credentialsPath, 'utf-8');
    return JSON.parse(content);
  } catch (error) {
    console.log(`❌ Error parsing credentials file: ${error instanceof Error ? error.message : error}`);
    return null;
  }
}

function tokenExpired(expiresAtMs: number): boolean {
  // Add 60 minutes buffer to refresh before actual expiry
  const bufferMs = 60 * 60 * 1000;
  const currentTimeMs = Date.now();
  return currentTimeMs >= (expiresAtMs - bufferMs);
}

async function performRefresh(refreshToken: string): Promise<ClaudeOAuthData | null> {
  try {
    const response = await fetch(OAUTH_TOKEN_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        grant_type: 'refresh_token',
        refresh_token: refreshToken,
        client_id: CLIENT_ID,
      }),
    });

    if (response.ok) {
      const data: TokenRefreshResponse = await response.json();
      
      return {
        accessToken: data.access_token,
        refreshToken: data.refresh_token,
        expiresAt: (Math.floor(Date.now() / 1000) + data.expires_in) * 1000,
        scopes: data.scope ? data.scope.split(' ') : ['user:inference', 'user:profile'],
        isMax: true,
      };
    } else {
      const errorBody = await response.text();
      console.log(`❌ Token refresh failed: ${response.status} - ${errorBody}`);
      return null;
    }
  } catch (error) {
    console.log(`❌ Error making refresh request: ${error instanceof Error ? error.message : error}`);
    return null;
  }
}

function formatTime(timestampMs: number): string {
  return new Date(timestampMs).toLocaleString('en-US', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  });
}

// Main function - simplified to take credentials path as argument
async function refreshTokenIfNeeded(credentialsPath: string): Promise<{ success: boolean; refreshed: boolean }> {
  console.log(`🔍 Checking OAuth credentials at: ${credentialsPath}`);
  
  const credentials = loadCredentials(credentialsPath);
  if (!credentials?.claudeAiOauth) {
    return { success: false, refreshed: false };
  }

  const oauthData = credentials.claudeAiOauth;
  const { refreshToken: refreshTokenValue, expiresAt } = oauthData;

  console.log(`📅 Current token expires at: ${formatTime(expiresAt)}`);
  
  if (!tokenExpired(expiresAt)) {
    console.log(`✅ Token is still valid (expires in ${Math.round((expiresAt - Date.now()) / 1000 / 60)} minutes)`);
    return { success: true, refreshed: false };
  }

  console.log(`🔄 Token expired or expiring soon, refreshing...`);
  const newTokens = await performRefresh(refreshTokenValue);
  
  if (newTokens) {
    try {
      credentials.claudeAiOauth = newTokens;
      await writeFile(credentialsPath, JSON.stringify(credentials, null, 2));
      console.log(`✅ Token refreshed successfully! New expiry: ${formatTime(newTokens.expiresAt)}`);
      
      // Output refresh status for GitHub Actions (modern syntax)
      if (process.env.GITHUB_OUTPUT) {
        try {
          const fs = await import('fs/promises');
          await fs.appendFile(process.env.GITHUB_OUTPUT, 'token_refreshed=true\n');
        } catch (error) {
          console.log(`Warning: Could not write to GITHUB_OUTPUT: ${error}`);
        }
      }
      
      return { success: true, refreshed: true };
    } catch (error) {
      console.log(`❌ Error updating credentials file: ${error instanceof Error ? error.message : error}`);
      return { success: false, refreshed: false };
    }
  }
  
  console.log(`❌ Failed to refresh token`);
  return { success: false, refreshed: false };
}

// Main execution
async function main(): Promise<void> {
  const args = process.argv.slice(2);
  
  if (args.length === 0 || args.includes('--help') || args.includes('-h')) {
    console.log(`Usage: ${process.argv[1]} <credentials-file-path>`);
    console.log('  credentials-file-path    Path to the credentials.json file');
    process.exit(args.includes('--help') || args.includes('-h') ? 0 : 1);
  }
  
  const credentialsPath = args[0];
  const result = await refreshTokenIfNeeded(credentialsPath);
  process.exit(result.success ? 0 : 1);
}

// Run main function if this file is executed directly
if (import.meta.main) {
  main().catch((error) => {
    console.error('❌ Unexpected error:', error);
    process.exit(1);
  });
}