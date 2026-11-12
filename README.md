# Merged PR Exporter

A single-file Ruby script that fetches all merged pull requests for a GitHub repository and writes them to a CSV file. Each row contains PR details, plus profile details for both the PR author and the user who merged it.

## What it does

1. Pages through every closed PR in the repo (`GET /repos/{owner}/{repo}/pulls`) by following the `Link` header, and keeps only those that were merged.
2. Fetches each merged PR's detail (`GET /repos/{owner}/{repo}/pulls/{number}`), since the list endpoint omits additions, deletions and the merger.
3. Fetches the author's and merger's profiles (`GET /users/{login}`), cached per user.
4. Writes one CSV row per merged PR.

### CSV columns

| Group | Columns |
| --- | --- |
| PR | `number`, `title`, `state`, `draft`, `html_url`, `base_branch`, `head_branch`, `labels`, `commits`, `changed_files`, `comments`, `review_comments`, `merge_commit_sha`, `body` |
| Required metrics | `additions`, `deletions`, `created_at`, `merged_at`, `time_to_merge_hours` |
| Author (`author_*`) | `login`, `id`, `type`, `site_admin`, `name`, `email`, `company`, `location`, `blog`, `bio`, `twitter_username`, `public_repos`, `public_gists`, `followers`, `following`, `created_at`, `html_url` |
| Merger (`merger_*`) | same fields as the author |

Missing or null values are written as empty cells. Note that `email` is only populated if the user has made it public.

## Requirements

- Ruby 2.6 or newer (macOS system Ruby works)
- No gems to install: the script uses only the standard library (`net/http`, `json`, `csv`, `optparse`)
- Internet access to `https://api.github.com`

Check your version with `ruby -v`.

## Installation

```sh
git clone https://github.com/StacySimmons/interview-script.git
cd interview-script
```

There is nothing else to install.

## Usage

```sh
ruby fetch_merged_prs.rb --repo owner/name [--output prs.csv] [--token TOKEN]
```

| Option | Environment variable | Default | Description |
| --- | --- | --- | --- |
| `-r`, `--repo` | `GITHUB_REPO` | required | Repository as `owner/name` |
| `-o`, `--output` | `OUTPUT_PATH` | `merged_prs.csv` | CSV file to write |
| `-t`, `--token` | `GITHUB_TOKEN` | none | Optional GitHub token |

Example:

```sh
ruby fetch_merged_prs.rb --repo StacySimmons/interview-script --output prs.csv
```

### Authentication and rate limits

A token is optional for public repos, but unauthenticated requests are limited to 60 per hour. Because the script makes one request per merged PR plus user lookups, larger repos need a token (5000 per hour):

```sh
export GITHUB_TOKEN=$(gh auth token)   # or a personal access token
ruby fetch_merged_prs.rb --repo owner/name
```

Prefer the environment variable over `--token` so the token doesn't end up in your shell history. Private repos need a token with read access.

## Error handling

- Requests time out after 10s (connect) / 30s (read).
- Network errors, HTTP 5xx, 429, and secondary rate limits (403 with `Retry-After`) are retried up to 4 attempts with exponential backoff. The script honors `Retry-After` but gives up if asked to wait more than 60s.
- Other 4xx errors fail immediately with a clear message.
- Exit codes: `0` success, `1` fetch or write failure, `2` invalid arguments.
- If an individual user profile can't be fetched, a warning is printed and that user's extra columns are left blank rather than failing the run.
