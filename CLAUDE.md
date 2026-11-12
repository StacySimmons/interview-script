You are helping me write a small, production-quality script during a timed technical assessment. Correctness on the first run matters more than cleverness. Follow the requirements exactly, and do not add features I did not ask for.

## Task (verbatim from the assessment)
Scripting Assessment:

1. Set Up a GitHub Sandbox
   - Create a repository in your GitHub account.
   - Use the GitHub CLI to make all changes, including commits and pull requests.
2. Make changes to your repository
   - Make a feature branch with some changes
   - Merge changes into the repository's master branch using necessary pull requests.
     - Create a Ruby Script
       - Write a script to fetch merged pull request data from the GitHub API.
       - Output the results to a CSV file. The CSV should include:
         a. Information about the author of the PR (GitHub user details).
         b. Information about the user who merged the PR (same as the author in this synthetic exercise).
         c. Details of the PR:
            i. Number of additions.
            ii. Number of deletions.
            iii. Timestamp when the PR was created.
            iv. Timestamp when the PR was merged.
            v. Time difference between creation and merge.
3. Deliverables
   - The GitHub repository showcasing commits and pull requests.
   - The Ruby/Rails script.
   - The generated CSV file contains the required data.

Beyond the required columns, include as many additional PR and author details as the API reasonably provides.

## Language and environment
- Language: Ruby
- Allowed dependencies: standard library only
- OS: macOS

## Repository / git workflow
- Use the GitHub CLI (`gh`) for all repo changes, commits, pushes, and pull requests.
- Work on a feature branch and merge via pull request; never commit directly to the default branch.
- The assessment says `master`; this repo's default branch is `main`. Treat `main` as the target unless told otherwise.
- Commit the script, the generated CSV, and this file so the deliverables are visible in the repo.

## Third-party service
- Service / base URL: https://api.github.com
- Endpoints:
  - `GET /repos/{owner}/{repo}/pulls?state=closed` (list; has no additions/deletions and no `merged_by`)
  - `GET /repos/{owner}/{repo}/pulls/{number}` (detail; has additions, deletions, `merged_by`, commits, changed_files, etc.)
  - `GET /users/{login}` (full author / merger profile: name, email, company, location, bio, followers, etc.)
- Authentication: Optional. Unauthenticated works for public repos at a low rate limit. Read the token from `GITHUB_TOKEN` or `--token`; never hardcode it.
- Pagination: `Link` response header with `rel="next"` (not a body field). Follow it until absent.
- Rate limits: 60 req/hr unauthenticated, 5000/hr with a token. Handle HTTP 429 and secondary-limit 403, honor `Retry-After`. Cache user lookups to limit request count.

## What the script must do
1. Fetch all closed PRs (paginated) and keep only merged ones (`merged_at` not null).
2. For each merged PR, fetch the PR detail and the author and merger user profiles (cached per login).
3. Write one CSV row per merged PR with: PR identity and metadata, additions, deletions, created_at, merged_at, time-to-merge, author details, and merger details (prefixed `author_` / `merger_`).

## Requirements
- Handle pagination fully so no records are missed.
- Set a timeout on every request.
- Retry transient failures (5xx, timeouts, 429) with exponential backoff, capped at a few attempts. Fail fast on 4xx other than 429 with a clear error message.
- Validate and defensively parse the response. Handle missing or null fields (including deleted users, where `user` is null) without crashing.
- Exit with a non-zero status and a helpful message on failure.
- Accept inputs (token, repo, output path) via environment variables or CLI arguments.
- Keep it in a single file, with small, well-named functions and a `main()` entry point.
- Add concise comments explaining the why, not the what.

## Output format
1. A one-paragraph summary of your approach and any assumptions you made.
2. The complete script in one code block, ready to run.
3. The exact commands to install any dependencies and run it.
4. A short list of edge cases you handled and any you deliberately did not.

If any requirement is ambiguous or the docs are missing something you need, list your questions before writing code. Otherwise, state your assumptions and proceed.
