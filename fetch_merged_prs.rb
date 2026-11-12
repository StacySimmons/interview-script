#!/usr/bin/env ruby
# frozen_string_literal: true

# Fetch merged pull requests from the GitHub REST API and write them to CSV.
#
# Usage:
#   ruby fetch_merged_prs.rb --repo owner/name [--output prs.csv] [--token TOKEN]
# Env fallbacks: GITHUB_REPO, OUTPUT_PATH, GITHUB_TOKEN (optional).

require 'net/http'
require 'json'
require 'csv'
require 'optparse'
require 'uri'
require 'time'

API_BASE        = 'https://api.github.com'
API_HOST        = 'api.github.com'
PER_PAGE        = 100 # API maximum; fewer round trips means fewer rate-limit hits
MAX_ATTEMPTS    = 4
OPEN_TIMEOUT    = 10
READ_TIMEOUT    = 30
MAX_RETRY_WAIT  = 60 # seconds; refuse to hang silently on long rate-limit resets
DEFAULT_OUTPUT  = 'merged_prs.csv'

TRANSIENT_NETWORK_ERRORS = [
  Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, EOFError,
  SocketError, Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ETIMEDOUT,
  Errno::EHOSTUNREACH, OpenSSL::SSL::SSLError
].freeze

USER_FIELDS = %w[
  login id type site_admin name email company location blog bio
  twitter_username public_repos public_gists followers following
  created_at html_url
].freeze

PR_HEADERS = %w[
  number title state draft html_url base_branch head_branch labels
  commits changed_files comments review_comments
  additions deletions created_at merged_at time_to_merge_hours
  merge_commit_sha body
].freeze

CSV_HEADERS = (
  PR_HEADERS +
  USER_FIELDS.map { |f| "author_#{f}" } +
  USER_FIELDS.map { |f| "merger_#{f}" }
).freeze

class FetchError < StandardError; end

# ---------- CLI / config ----------

def parse_options(argv)
  opts = {
    repo: ENV['GITHUB_REPO'],
    output: ENV['OUTPUT_PATH'] || DEFAULT_OUTPUT,
    token: ENV['GITHUB_TOKEN']
  }
  OptionParser.new do |o|
    o.banner = 'Usage: fetch_merged_prs.rb --repo owner/name [--output FILE] [--token TOKEN]'
    o.on('-r', '--repo OWNER/NAME', 'Repository (or env GITHUB_REPO)') { |v| opts[:repo] = v }
    o.on('-o', '--output FILE', "CSV path (or env OUTPUT_PATH, default #{DEFAULT_OUTPUT})") { |v| opts[:output] = v }
    o.on('-t', '--token TOKEN', 'Optional GitHub token (or env GITHUB_TOKEN)') { |v| opts[:token] = v }
  end.parse!(argv)

  opts[:token] = nil if opts[:token].to_s.strip.empty?
  validate_repo!(opts[:repo])
  opts
end

def validate_repo!(repo)
  return if repo.to_s.match?(%r{\A[\w.-]+/[\w.-]+\z})

  raise OptionParser::InvalidArgument, "repo must look like 'owner/name', got #{repo.inspect}"
end

# Fail before any network calls if the output location is unusable.
def validate_output_path!(path)
  dir = File.dirname(path)
  raise FetchError, "Output directory does not exist: #{dir}" unless File.directory?(dir)
  raise FetchError, "Output directory is not writable: #{dir}" unless File.writable?(dir)
end

# ---------- HTTP with retry ----------

def http_get(uri, token)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = OPEN_TIMEOUT
  http.read_timeout = READ_TIMEOUT
  http.write_timeout = READ_TIMEOUT

  req = Net::HTTP::Get.new(uri)
  req['Accept'] = 'application/vnd.github+json'
  req['X-GitHub-Api-Version'] = '2022-11-28'
  req['User-Agent'] = 'merged-pr-exporter' # GitHub rejects requests without a UA
  req['Authorization'] = "Bearer #{token}" if token
  http.request(req)
end

def backoff_seconds(attempt)
  2**(attempt - 1) # 1s, 2s, 4s
end

def rate_limit_exhausted?(res)
  res.code.to_i == 403 && res['x-ratelimit-remaining'] == '0'
end

# 429, 5xx, and 403 secondary rate limits (signalled by Retry-After) are worth retrying.
def retryable_status?(res)
  code = res.code.to_i
  code == 429 || code >= 500 || (code == 403 && res['retry-after'])
end

def retry_wait_seconds(res, attempt)
  header = res['retry-after']
  wait = header && header.match?(/\A\d+\z/) ? header.to_i : backoff_seconds(attempt)
  if wait > MAX_RETRY_WAIT
    raise FetchError, "Rate limited; server asked us to wait #{wait}s (limit #{MAX_RETRY_WAIT}s). Try again later or set GITHUB_TOKEN."
  end

  wait
end

def http_error_message(res)
  detail = begin
    JSON.parse(res.body.to_s)['message']
  rescue JSON::ParserError
    nil
  end
  hint = case res.code.to_i
         when 401 then ' (check GITHUB_TOKEN)'
         when 404 then ' (repo not found, or private and token lacks access)'
         when 403 then rate_limit_exhausted?(res) ? " (rate limit exhausted; resets at #{reset_time(res)}; set GITHUB_TOKEN for a higher limit)" : ''
         end
  "GitHub API returned HTTP #{res.code}: #{detail || res.message}#{hint}"
end

def reset_time(res)
  Time.at(res['x-ratelimit-reset'].to_i).utc.iso8601
rescue StandardError
  'unknown'
end

def request_with_retry(uri, token)
  attempt = 0
  loop do
    attempt += 1
    begin
      res = http_get(uri, token)
    rescue *TRANSIENT_NETWORK_ERRORS => e
      raise FetchError, "Network error after #{attempt} attempts: #{e.class}: #{e.message}" if attempt >= MAX_ATTEMPTS

      warn "Transient network error (#{e.class}); retrying (#{attempt}/#{MAX_ATTEMPTS})"
      sleep backoff_seconds(attempt)
      next
    end

    return res if res.is_a?(Net::HTTPSuccess)
    raise FetchError, http_error_message(res) unless retryable_status?(res)
    raise FetchError, "#{http_error_message(res)} (gave up after #{attempt} attempts)" if attempt >= MAX_ATTEMPTS

    wait = retry_wait_seconds(res, attempt)
    warn "HTTP #{res.code}; retrying in #{wait}s (#{attempt}/#{MAX_ATTEMPTS})"
    sleep wait
  end
end

# ---------- Pagination ----------

# GitHub paginates via the Link response header (rel="next"), not a body field.
def next_page_url(res)
  link = res['link']
  return nil unless link

  match = link.match(/<([^>]+)>\s*;\s*rel="next"/)
  return nil unless match

  uri = URI.parse(match[1])
  # Never forward our token to a host other than the API.
  raise FetchError, "Unexpected pagination URL host: #{uri.host}" unless uri.host == API_HOST

  uri
rescue URI::InvalidURIError => e
  raise FetchError, "Malformed pagination URL: #{e.message}"
end

def parse_json(res, expected_class)
  data = JSON.parse(res.body.to_s)
  raise FetchError, "Expected a JSON #{expected_class} from the API, got #{data.class}" unless data.is_a?(expected_class)

  data
rescue JSON::ParserError => e
  raise FetchError, "Response was not valid JSON: #{e.message}"
end

def parse_page(res)
  parse_json(res, Array)
end

# The /pulls endpoint has no "merged" filter, so we pull all closed PRs and filter locally.
def fetch_closed_pulls(repo, token)
  uri = URI("#{API_BASE}/repos/#{repo}/pulls?state=closed&sort=updated&direction=desc&per_page=#{PER_PAGE}")
  pulls = []
  page = 0
  while uri
    page += 1
    res = request_with_retry(uri, token)
    items = parse_page(res)
    pulls.concat(items)
    warn "Fetched page #{page} (#{items.size} PRs, #{pulls.size} total closed)"
    uri = next_page_url(res)
  end
  pulls
end

# ---------- Transform ----------

def merged?(pr)
  pr.is_a?(Hash) && !pr['merged_at'].nil? # closed-without-merge PRs have merged_at = null
end

# additions/deletions are only returned by the single-PR endpoint, not the list endpoint,
# so each merged PR costs one extra request.
def fetch_pull_detail(repo, number, token)
  res = request_with_retry(URI("#{API_BASE}/repos/#{repo}/pulls/#{number}"), token)
  parse_json(res, Hash)
end

def fetch_details(repo, merged_list, token)
  merged_list.each_with_index.map do |pr, idx|
    number = pr['number']
    if number.nil?
      warn 'Skipping a merged PR with no number in the list response'
      next
    end
    warn "Fetching PR details #{idx + 1}/#{merged_list.size}" if ((idx + 1) % 25).zero? || idx.zero?
    fetch_pull_detail(repo, number, token)
  end.compact # `next` above yields nil for skipped PRs
end

def hours_between(start_str, end_str)
  return nil if start_str.nil? || end_str.nil?

  ((Time.iso8601(end_str) - Time.iso8601(start_str)) / 3600.0).round(2)
rescue ArgumentError
  nil
end

# The PR payload only embeds a partial user; the full profile (name, email, followers...)
# needs /users/{login}. Cache by login since author and merger are often the same person.
def fetch_user(login, token, cache)
  return {} if login.to_s.empty? # deleted accounts come back as user: null

  cache[login] ||= begin
    res = request_with_retry(URI("#{API_BASE}/users/#{URI.encode_www_form_component(login)}"), token)
    parse_json(res, Hash)
  rescue FetchError => e
    # One unreachable profile should not discard the whole export.
    warn "Could not fetch user #{login}: #{e.message}"
    {}
  end
end

def user_columns(profile, embedded)
  # Fall back to the embedded stub so login/id/url survive a failed profile lookup.
  merged = (embedded || {}).merge(profile)
  USER_FIELDS.map { |f| merged[f] }
end

def pr_to_row(pr, token, cache)
  author = pr['user']
  merger = pr['merged_by']
  author_profile = fetch_user(author && author['login'], token, cache)
  merger_profile = fetch_user(merger && merger['login'], token, cache)

  [
    pr['number'], pr['title'], pr['state'], pr['draft'], pr['html_url'],
    pr.dig('base', 'ref'), pr.dig('head', 'ref'),
    Array(pr['labels']).map { |l| l.is_a?(Hash) ? l['name'] : nil }.compact.join('; '),
    pr['commits'], pr['changed_files'], pr['comments'], pr['review_comments'],
    pr['additions'], pr['deletions'],
    pr['created_at'], pr['merged_at'],
    hours_between(pr['created_at'], pr['merged_at']),
    pr['merge_commit_sha'], pr['body']
  ] + user_columns(author_profile, author) + user_columns(merger_profile, merger)
end

# ---------- Output ----------

def write_csv(path, rows)
  CSV.open(path, 'w', encoding: 'UTF-8') do |csv|
    csv << CSV_HEADERS
    rows.each { |row| csv << row }
  end
rescue SystemCallError => e
  raise FetchError, "Could not write #{path}: #{e.message}"
end

# ---------- Entry point ----------

def main
  opts = parse_options(ARGV)
  validate_output_path!(opts[:output])

  pulls = fetch_closed_pulls(opts[:repo], opts[:token])
  merged = pulls.select { |pr| merged?(pr) }
  details = fetch_details(opts[:repo], merged, opts[:token])
  user_cache = {}
  write_csv(opts[:output], details.map { |pr| pr_to_row(pr, opts[:token], user_cache) })

  puts "Wrote #{merged.size} merged PRs (of #{pulls.size} closed) from #{opts[:repo]} to #{opts[:output]}"
rescue OptionParser::ParseError => e
  warn "Error: #{e.message}"
  exit 2
rescue FetchError => e
  warn "Error: #{e.message}"
  exit 1
end

main if $PROGRAM_NAME == __FILE__
