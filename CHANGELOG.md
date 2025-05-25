# Changelog

## Fork Changes (grll/claude-code-action@beta)

This is a fork of the official Claude Code Action that adds OAuth authentication support for Claude Max subscribers.

### Added

- **OAuth Authentication Support**: Claude Max subscribers can now use their subscription in GitHub Actions
  - New input: `use_oauth` - Enable OAuth authentication
  - New input: `claude_access_token` - OAuth access token from Claude Max subscription
  - New input: `claude_refresh_token` - OAuth refresh token from Claude Max subscription
  - New input: `claude_expires_at` - Token expiration timestamp

- **Updated Base Action**: Uses `grll/claude-code-base-action@beta` which includes OAuth credential handling

### Changed

- Action name updated to "Claude Code Action (OAuth Fork)" to clarify fork purpose
- README documentation updated to include OAuth setup instructions
- All examples updated to use the forked action

### How to Use OAuth

1. Get your OAuth credentials from your Claude Max subscription
2. Add the credentials as GitHub secrets:
   - `CLAUDE_ACCESS_TOKEN`
   - `CLAUDE_REFRESH_TOKEN`
   - `CLAUDE_EXPIRES_AT`
3. Enable OAuth in your workflow:
   ```yaml
   - uses: grll/claude-code-action@beta
     with:
       use_oauth: "true"
       claude_access_token: ${{ secrets.CLAUDE_ACCESS_TOKEN }}
       claude_refresh_token: ${{ secrets.CLAUDE_REFRESH_TOKEN }}
       claude_expires_at: ${{ secrets.CLAUDE_EXPIRES_AT }}
   ```

### Compatibility

This fork maintains full backward compatibility with the original action. All existing workflows will continue to work without changes. OAuth is an optional authentication method alongside the existing options (API key, Bedrock, Vertex AI).