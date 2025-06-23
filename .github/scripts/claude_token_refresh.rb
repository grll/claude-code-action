#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'time'
require 'uri'

class ClaudeTokenRefresher
  OAUTH_TOKEN_URL = 'https://console.anthropic.com/v1/oauth/token'
  CLIENT_ID = '9d1c250a-e61b-44d9-88ed-5944d1962f5e'
  CREDENTIALS_PATH = 'credentials.json'

  def initialize(credentials_path = CREDENTIALS_PATH)
    @credentials_path = credentials_path
  end

  def refresh_token
    credentials = load_credentials
    
    if credentials.nil? || credentials['claudeAiOauth'].nil?
      puts "Error: No valid credentials found in #{@credentials_path}"
      return false
    end

    oauth_data = credentials['claudeAiOauth']
    refresh_token = oauth_data['refreshToken']
    expires_at = oauth_data['expiresAt']

    puts "Current token expires at: #{Time.at(expires_at / 1000).strftime('%Y-%m-%d %H:%M:%S')}"
    puts "Token expired: #{token_expired?(expires_at)}"
    
    if !token_expired?(expires_at) && !force_refresh?
      puts "Token is still valid. Use --force to refresh anyway."
      
      # Output current tokens for GitHub Actions
      output_tokens(oauth_data)
      return true
    end

    puts "Refreshing token..."
    new_tokens = perform_refresh(refresh_token)
    
    if new_tokens
      update_credentials(credentials, new_tokens)
      puts "Token refreshed successfully!"
      puts "New token expires at: #{Time.at(new_tokens['expiresAt'] / 1000).strftime('%Y-%m-%d %H:%M:%S')}"
      
      # Output new tokens for GitHub Actions
      output_tokens(new_tokens)
      true
    else
      puts "Failed to refresh token"
      false
    end
  end

  private

  def load_credentials
    return nil unless File.exist?(@credentials_path)
    
    JSON.parse(File.read(@credentials_path))
  rescue JSON::ParserError => e
    puts "Error parsing credentials file: #{e.message}"
    nil
  end

  def token_expired?(expires_at_ms)
    # Add 60 minutes buffer to refresh before actual expiry
    buffer_ms = 60 * 60 * 1000
    current_time_ms = Time.now.to_i * 1000
    current_time_ms >= (expires_at_ms - buffer_ms)
  end

  def force_refresh?
    ARGV.include?('--force') || ARGV.include?('-f')
  end

  def perform_refresh(refresh_token)
    uri = URI(OAUTH_TOKEN_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = {
      grant_type: 'refresh_token',
      refresh_token: refresh_token,
      client_id: CLIENT_ID
    }.to_json

    begin
      response = http.request(request)
      
      if response.code == '200'
        data = JSON.parse(response.body)
        
        {
          'accessToken' => data['access_token'],
          'refreshToken' => data['refresh_token'],
          'expiresAt' => (Time.now.to_i + data['expires_in']) * 1000,
          'scopes' => data['scope'] ? data['scope'].split(' ') : ['user:inference', 'user:profile'],
          'isMax' => true
        }
      else
        puts "Error response: #{response.code} - #{response.body}"
        nil
      end
    rescue => e
      puts "Error making refresh request: #{e.message}"
      nil
    end
  end

  def update_credentials(credentials, new_tokens)
    credentials['claudeAiOauth'] = new_tokens
    
    File.write(@credentials_path, JSON.pretty_generate(credentials))
  rescue => e
    puts "Error updating credentials file: #{e.message}"
    false
  end

  def output_tokens(oauth_data)
    # Output tokens as GitHub Actions outputs (new format)
    File.open(ENV['GITHUB_OUTPUT'], 'a') do |f|
      f.puts "access_token=#{oauth_data['accessToken']}"
      f.puts "refresh_token=#{oauth_data['refreshToken']}"
      f.puts "expires_at=#{oauth_data['expiresAt']}"
    end if ENV['GITHUB_OUTPUT']
    
    # Mask sensitive values in logs
    puts "::add-mask::#{oauth_data['accessToken']}"
    puts "::add-mask::#{oauth_data['refreshToken']}"
  end
end

if __FILE__ == $0
  refresher = ClaudeTokenRefresher.new
  
  if ARGV.include?('--help') || ARGV.include?('-h')
    puts "Usage: #{$0} [--force|-f] [--path PATH]"
    puts "  --force, -f    Force refresh even if token is still valid"
    puts "  --path PATH    Custom path to credentials.json file"
    puts "  --help, -h     Show this help message"
    exit 0
  end
  
  custom_path_index = ARGV.index('--path')
  if custom_path_index && ARGV[custom_path_index + 1]
    refresher = ClaudeTokenRefresher.new(ARGV[custom_path_index + 1])
  end
  
  success = refresher.refresh_token
  exit(success ? 0 : 1)
end