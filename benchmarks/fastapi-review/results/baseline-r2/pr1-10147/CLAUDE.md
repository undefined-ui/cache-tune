# FastAPI — project notes

Today's date: 2026-10-30
Current branch: review/pr-10147

## What this is
FastAPI is a Python web framework for building APIs, built on Starlette (HTTP/ASGI) and Pydantic (validation/serialization).

## Layout
- `fastapi/` — library source
  - `applications.py` — the `FastAPI` app class
  - `routing.py` — `APIRouter`, `APIRoute`, request handling, streaming (SSE/JSONL)
  - `dependencies/utils.py` — dependency resolution, request parameter extraction and validation
  - `params.py`, `param_functions.py` — `Query`, `Header`, `Body`, `Form`, etc.
  - `security/` — security schemes (API key, HTTP basic/bearer, OAuth2, OpenID Connect)
  - `openapi/` — OpenAPI schema generation
  - `encoders.py` — `jsonable_encoder`
- `tests/` — pytest suite, mirrors features; `docs_src/` holds tutorial code that tests import
- `docs/en/docs/` — documentation; `release-notes.md` is updated per PR

## Conventions
- Python 3.9+; full type hints; public params documented with `Annotated[..., Doc(...)]`
- Keep backwards compatibility; deprecations go through warnings first
- Pydantic v2 only
- Every behavior change needs tests; coverage is expected to stay at 100%
- Format/lint with ruff; type-check with mypy

## Testing
- `uv run pytest tests/` (or `pytest tests/path::test_name`)
