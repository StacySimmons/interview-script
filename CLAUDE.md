You are helping me write a small, production-quality script during a timed technical assessment. Correctness on the first run matters more than cleverness. Follow the requirements exactly, and do not add features I did not ask for.

## Task (verbatim from the assessment)
Write a script to fetch merged pull request data from the GitHub API. Output the results to a CSV file. The CSV should include:
Give me as many details about the PR and author as possible.

## Language and environment
- Language: Ruby
- Allowed dependencies: standard
- OS: macOS

## Third-party service
- Service / base URL: (https://api.github.com)
- Endpoint(s) I need: GET /repos/{owner}/{repo}/pulls
- Authentication: None. Read credentials from environment variables, never hardcode them.
- Pagination: check, I think it's nextPage
- Rate limits: [known limits, or unknown, so handle HTTP 429 and honor Retry-After]
- API docs / sample response (pasted below):
[PASTE DOCS OR A SAMPLE JSON RESPONSE]

## What the script must do 
1. [Fetch data from ...]
2. [Filter / transform / aggregate ...]
3. [Output: print to stdout / write to a file / save as CSV / JSON, with this format ...]

## Requirements
- Handle pagination fully so no records are missed.
- Set a timeout on every request.
- Retry transient failures (5xx, timeouts, 429) with exponential backoff, capped at a few attempts. Fail fast on 4xx other than 429 with a clear error message.
- Validate and defensively parse the response. Handle missing or null fields without crashing.
- Exit with a non-zero status and a helpful message on failure.
- Accept inputs (e.g., API key, query parameters, output path) via environment variables or CLI arguments.
- Keep it in a single file, with small, well-named functions and a `main()` entry point.
- Add concise comments explaining the why, not the what.

## Output format
1. A one-paragraph summary of your approach and any assumptions you made.
2. The complete script in one code block, ready to run.
3. The exact commands to install any dependencies and run it.
4. A short list of edge cases you handled and any you deliberately did not.

If any requirement is ambiguous or the docs are missing something you need, list your questions before writing code. Otherwise, state your assumptions and proceed.