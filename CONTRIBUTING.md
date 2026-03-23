# Contributing to AutoResearchClaw

## Setup

1. Fork and clone the repo
2. Install dependencies with Poetry (including dev tools):

   ```bash
   poetry install --with dev
   ```

3. Generate your local config:

   ```bash
   poetry run researchclaw init
   ```

4. Edit `config.arc.yaml` with your LLM settings

## Config Convention

- `config.researchclaw.example.yaml` — tracked template (do not add secrets)
- `config.arc.yaml` — your local config (gitignored, created by `researchclaw init`)
- `config.yaml` — also gitignored, supported as fallback

## Running Tests

```bash
poetry run pytest tests/
```

## Checking Your Environment

```bash
poetry run researchclaw doctor
```

## PR Guidelines

- Branch from main
- One concern per PR
- Ensure `poetry run pytest tests/` passes
- Include tests for new functionality
