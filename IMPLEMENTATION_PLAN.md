# Rageg — Implementation Plan

This document captures the follow-up work identified during the full project
audit. It is organized in two parts:

1. **Priority implementation items** — the fixes from the audit's "Suggested
   priority order", expanded with context and concrete guidance.
2. **Creative ideas & roadmap** — larger, optional improvements for later.

---

## Priority Implementation Items

### 1. Fix secrets-to-browser + add an auth gate + gate destructive MCP tools

**Context.** `RagegWeb.ConfigurationLive` loads the *actual* API key values into
the form via `Rageg.AIKeys.get_config/0` → `to_form/2`, and
`Rageg.AIKeys.save_config/1` persists them in plaintext at
`~/.rageg/.ai_keys.json`. Even though the inputs are rendered as
`type="password"`, the real key strings are present in the HTML and readable via
view-source / DevTools.

The app also exposes powerful, state-changing capabilities with no
authentication: arbitrary dllb query execution (`/dllb/graph`, `/dllb/search`),
arbitrary MCP tool execution (`/mcp`) including tools with
`destruction_level` up to `"full"`, file-rewriting refactors, a global
"Reset All State" button, and "open file in editor".

**Work items.**

- [ ] Stop sending real key values to the client:
  - Return masked placeholders (`""` or `"••••1234"`) from
    `Rageg.AIKeys.get_config/0`.
  - Only persist a key when the user enters a new value; keep the existing
    value unchanged otherwise.
- [ ] Harden key persistence:
  - `File.mkdir_p!` then `File.chmod` the config file to `0o600`.
  - Consider a comment/doc note recommending OS keychain for future work.
- [ ] Add a minimal authentication layer if the app is ever reachable beyond
  loopback:
  - Basic-auth plug or `mix phx.gen.auth`-style session auth.
  - Default prod binding to loopback and document reverse-proxy auth.
- [ ] Gate destructive MCP tool execution:
  - Add an explicit confirmation step for tools whose `destruction_level`
    is not `:none`.
  - Show the tool name, target, and risk before executing.

---

### 2. Remove unbounded atom creation from user input

**Context.** The following call `String.to_atom/1` on user-supplied module,
function, or parameter names — a VM memory-leak / exhaustion risk that
`AGENTS.md` explicitly forbids:

- `Rageg.Refactor.safe_atom/1`
- `Rageg.Impact.safe_atom/1`
- `Rageg.Plugins.normalize_id/1`
- `RagegWeb.RefactorLive.safe_key_atom/1`

**Work items.**

- [ ] Replace `String.to_atom/1` fallbacks with `String.to_existing_atom/1`.
- [ ] Return `{:error, :unknown_atom}` (or a friendly error message) for atoms
  that are not already loaded.
- [ ] Validate against a fixed allowlist where the set of valid values is known
  (e.g., visibility `:public`/`:private`, provider names, operation names).

---

### 3. Fix parameterized dllb writes (injection/corruption surface)

**Context.** `Rageg.Metacredo.save_cached_result_dllb/2` builds:

```elixir
query = "CREATE _metacredo_cache:#{id} SET payload = '#{escaped_json}' ON CONFLICT UPDATE"
```

with only `String.replace(json, "'", "''")`. This is fragile for JSON payloads
containing backslashes, newlines, and other characters, and is a latent
query-injection/corruption risk.

**Work items.**

- [ ] Replace string-interpolated writes with dllb's parameterized/batch API
  (bind values) where available.
- [ ] If parameters are not supported, implement correct escaping for the
  actual dllb query language.
- [ ] Audit any other `Rageg.Dllb.query/1` / `batch_transaction/2` call sites
  that interpolate user data.

---

### 4. Fix broken LiveView inputs and the MCP schema mismatch

**Context.** A recurring pattern sends a hardcoded empty `phx-value-*` and omits
`name`, so typed values never reach the server:

- `lib/rageg_web/live/mcp_live.ex`
  - Search box: `phx-keyup="search_tools" phx-value-query=""`.
  - Form text/number/select inputs: `phx-keyup/phx-change="update_form_arg"`
    with `phx-value-value=""`.
  - JSON textarea: `phx-keyup="update_json" phx-value-json=""`.
- `lib/rageg_web/live/metacredo_live.ex`
  - Search box: `phx-keyup="update_search" phx-value-query=""`.

Additionally, `Rageg.MCP.normalize_tool_schema/1` stringifies `inputSchema`
keys recursively but keeps the envelope key as an atom, while
`RagegWeb.McpLive.get_schema_properties/1` does not match the resulting mixed
`%{inputSchema: %{"properties" => ...}}` shape. As a result, the dynamic MCP
parameter form reports "This tool takes no parameters" for every tool.

**Work items.**

- [ ] Add `name="..."` attributes (or dynamic `phx-value-X={@value}`) to all
  search/filter/form inputs; remove hardcoded `phx-value-value=""`.
- [ ] Standardize `inputSchema` on a single key convention (all string keys or
  all atom keys) and make `get_schema_properties/1` match exactly what
  `normalize_tool_schema/1` produces.
- [ ] Add tests asserting rendered inputs carry `name` attributes (or correct
  `phx-value` bindings) so this class of bug is caught.

---

### 5. De-block the `Profiles` GenServer

**Context.** `Rageg.Profiles.handle_call({:switch, ...})` runs
`activate_project/2` synchronously inside the GenServer (including
`GraphStore.load_project/1`, dllb ingestion, and a Bumblebee readiness wait)
with a `:infinity` timeout. The `:create` path correctly offloads to a `Task`,
but `:switch` does not.

**Work items.**

- [ ] Make `:switch` reply immediately and perform activation in a supervised
  `Task`, mirroring the `:create` flow.
- [ ] Publish progress via PubSub / `send_update` instead of running
  `on_progress` callbacks inside the GenServer.
- [ ] Ensure the returned profile status transitions (`indexing` → `ready` /
  `error`) are handled consistently by the background task.

---

### 6. Extract shared Markdown / editor / prompt modules (DRY)

**Context.** The following are duplicated almost verbatim:

- `open_file_in_editor/2` in `RagegWeb.ChatLive` and `RagegWeb.AuditLive`.
- `render_markdown/1`, `insert_intermediate_links/1`, and
  `convert_ide_links/1` in `RagegWeb.ChatLive` and `RagegWeb.AuditLive`
  (with a separate variant in `RagegWeb.AssessLive`).
- Large inline prompt strings and multi-arg helper functions in
  `Rageg.Assess`.

**Work items.**

- [ ] Add `RagegWeb.Markdown` for MDEx rendering + `ide://` link conversion.
- [ ] Add `RagegWeb.EditorOpener` for the editor-opening logic.
- [ ] Add `Rageg.Assess.Prompt` for the PR review system/user prompts.
- [ ] Replace the duplicated implementations with calls to the shared modules.

---

### 7. Test hygiene

**Context.** Several testing issues were found:

- `RagegWeb.ConnCase` creates a temp dir + profile per test but never removes
  them on exit, accumulating profiles under `~/.rageg/profiles`.
- `test_helper.exs` is bare (`ExUnit.start()`), and some `async: true` tests
  mutate global application env (e.g., `Application.put_env(:dllb, ...)`),
  which can race across tests.
- `Rageg.StatsTest` has a misleading "server is running" test comment.
- The broken `phx-value` inputs are not caught because LiveView tests submit
  events with explicit params independent of DOM wiring.

**Work items.**

- [ ] Add `on_exit` cleanup in `ConnCase` for the temp dir and created profile.
- [ ] Set `async: false` for any test that mutates global app env or the
  filesystem.
- [ ] Fix/remove the misleading `StatsTest` case.
- [ ] Add rendered-attribute assertions (e.g., `name=` present) for form/search
  inputs, and/or a Playwright integration check for MCP/MetaCredo search.

---

### 8. Polish items from the audit

**Context.** Smaller, mostly cosmetic or consistency issues:

- `hero-wrench-Screwdriver` icon in `mcp_live.ex` has incorrect casing.
- Dashboard "Density" is always `0.0`.
- Mixed JSON libraries (`:json` vs `Jason`).
- `.formatter.exs` disables the LiveView HTML formatter.
- `.credo.exs` disables several valuable checks and `strict: false`.
- `ARCHITECTURE.md`/`README.md` doc drift.
- Unused `RagegWeb.Telemetry.metrics/0` and missing reporter.
- i18n gaps in the MCP page.
- `RagegWeb.static_paths/0` references a missing `robots.txt`.

**Work items.**

- [ ] Fix the `hero-wrench-Screwdriver` icon casing.
- [ ] Compute density (`edges / (n * (n - 1))`) or remove the dashboard card.
- [ ] Standardize on one JSON library.
- [ ] Enable `Phoenix.LiveView.HTMLFormatter` in `.formatter.exs`.
- [ ] Enable strict Credo in CI (via the existing `quality.ci` alias).
- [ ] Update `ARCHITECTURE.md` and `README.md` to match reality.
- [ ] Attach a telemetry reporter or remove the unused metrics scaffolding.
- [ ] Wrap remaining MCP-page strings in `gettext`.
- [ ] Add or drop `robots.txt`.

---

## Creative Ideas & Roadmap

### A. Auth + "trusted workspace" mode (highest leverage)

A one-time setup passphrase stored hashed in `~/.rageg`, enforced by a plug,
plus an allowlist of directories the app may ingest/refactor. This turns a
dangerous local tool into a safely-shareable team tool.

**Status: partially implemented.**

- [x] Directory allowlist: `Rageg.Workspace` (configured with
  `config :rageg, :allowed_roots` / `RAGEG_ALLOWED_ROOTS`), enforced in
  `Rageg.Profiles.create/3`, `Rageg.Profiles.switch/2` and `Rageg.Analyze.run/2`.
  Paths are `~`-expanded, symlink-resolved and `..`-normalised before the
  check; an empty allowlist means "no restriction" (local default).
- [x] Basic-auth plug (`RagegWeb.Plugs.BasicAuth`) + loopback-only prod bind.
- [ ] One-time passphrase stored hashed in `~/.rageg` (superseded for now by
  env-configured basic auth; revisit if per-user accounts are needed).

### B. LiveView streams everywhere

Adopt LiveView streams for tables/lists (Quality, Dependencies, chat messages,
analyze progress). This reduces memory and enables efficient
`phx-update="stream"` diffing, and aligns with the project's own `AGENTS.md`
guidance. `MetacredoLive` already paginates manually; streams would simplify it.

**Status: partially implemented.**

- [x] `ChatLive`: messages and tool-call sidebar are streams
  (`#chat-messages`, `#chat-tool-calls`), with an empty state that works via
  `only:` variants.
- [ ] Quality / Dependencies / analyze-progress tables.

### C. Supervised task runner

Replace the ad-hoc `Task.start` + `Process.monitor` pattern used across six or
more LiveViews with a `Task.Supervisor` in the supervision tree. Long jobs become
cancelable, observable, and don't orphan on LiveView disconnect.

**Status: implemented** (`Rageg.TaskRunner`).

- [x] Every LiveView job (analyze, URL analyze, assess, audit, chat, impact,
  metacredo, refactor execute/preview, MCP tool execution) now goes through
  `TaskRunner.start/4`, which supervises the job, delivers
  `{:task_result, tag, result}` / `{:task_error, tag, reason}`, and tracks jobs
  per owner.
- [x] `TaskRunner.cancel/1` replaces `Process.exit(pid, :kill)`; cancel
  buttons use it.
- [ ] Automatic cancellation on LiveView terminate (jobs are tracked per owner
  but not yet killed on `terminate/2`).

### D. Safety gate for destructive MCP tools

Show a confirmation modal listing the tool's `destruction_level`, affected
target, and a "dry-run first" toggle for `refactor` / `edit` / `rollback` tools.
This complements the existing `destruction_level_badge` UI, which currently
does nothing to prevent execution.

**Status: implemented.**

### H. CI pipeline

Add a GitHub Actions workflow running
`mix rageg.ci --base origin/$GITHUB_BASE_REF --format github`. The
`Mix.Tasks.Rageg.Ci` task already exists and is purpose-built for this.

**Status: implemented** (`.github/workflows/ci.yml`).

- [x] `test` job: deps cache, `mix compile --warnings-as-errors`,
  `mix format --check-formatted`, `mix credo --strict`, `mix test`.
- [x] `quality-gate` job (pull requests only):
  `mix rageg.ci --base origin/${{ github.base_ref }} --format github`.

### I. Custom error pages + error reporting

Add custom 404/500 pages and a real error-reporting backend (Sentry or
LoggerJSON) instead of relying on silent rescues.

**Status: partially implemented.**

- [x] Styled, chrome-free 404/500/other error pages in
  `RagegWeb.ErrorHTML` (with a link back to the dashboard and a generic
  fallback for unhandled statuses).
- [x] `Rageg.Diagnostics` makes silent rescues observable (counted,
  rate-limited logging, UI banner).
- [ ] External error reporting backend (Sentry / LoggerJSON).

### J. Property-based tests

Use StreamData for pure functions like `Rageg.Graph.prettify_id/1` and
`Rageg.Impact.parse_node_ref/1` (round-trip and format-stability properties),
which are currently covered only by hand-written cases.

**Status: implemented.**

- [x] `stream_data` added as a test-only dependency.
- [x] `test/rageg/graph_property_test.exs`: idempotence and format stability
  of `prettify_id/1`, tuple round-trips, and "never raises on arbitrary
  input".
- [x] `test/rageg/impact_property_test.exs`: `parse_node_ref/1` ⇄
  `format_ref/1` round-trips for function and module refs, idempotence, and
  the "unknown atoms are rejected, never created" guarantee.
- [x] `Rageg.Impact.parse_node_ref/1` and `format_ref/1` are now public (they
  were private) so they can be exercised directly.
buttons.

**Status: partially implemented.**

- [x] "Preview → confirm → apply" workflow: Apply is disabled until a preview
  exists, blocking conflicts prevent confirmation, and a confirmation modal
  lists the files and +/- counts before anything is written.
- [ ] The `:Dummy` module is still used for `change_signature` and
  `inline_function` previews (needs a fix in Ragex's `Refactor.Elixir` API).

### G. Real PCA via Nx + web-worker graph layout

Replace the hand-rolled PCA in `Rageg.Embeddings.project_2d/1` with a proper
`Nx.LinAlg` SVD/eigh (Nx/EXLA are already dependencies). Move D3 force-simulation
layout to a web worker to keep the browser main thread smooth at 1000 nodes.

**Status: implemented.**

- [x] `Rageg.Embeddings.project_2d/1` now mean-centres the data and projects it
  onto the first two right singular vectors from `Nx.LinAlg.svd/1`, with a
  graceful fallback for degenerate input.
- [x] `assets/js/hooks/graph_layout_worker.js` runs the force simulation off
  the main thread (300 synchronous ticks) and posts back settled positions;
  `GraphHook` applies them in one pass and falls back to a local simulation
  when Workers are unavailable.

### H. CI pipeline

Add a GitHub Actions workflow running
`mix rageg.ci --base origin/$GITHUB_BASE_REF --format github`. The
`Mix.Tasks.Rageg.Ci` task already exists and is purpose-built for this.

### I. Custom error pages + error reporting

Add custom 404/500 pages and a real error-reporting backend (Sentry or
LoggerJSON) instead of relying on silent rescues.

**Status: partially implemented** -- `Rageg.Diagnostics` now makes silent
rescues observable (counted, rate-limited logging, UI banner); a dedicated
404/500 page and an external reporting backend are still open.

### J. Property-based tests

Use StreamData for pure functions like `Rageg.Graph.prettify_id/1` and
`Rageg.Impact.parse_node_ref/1` (round-trip and format-stability properties),
which are currently covered only by hand-written cases.