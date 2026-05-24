# Rageg Architecture

## Overview

Rageg is a Phoenix LiveView application that serves as the visual frontend for
the Ragex code analysis engine and the dllb multi-model database. It runs in the
same BEAM VM as Ragex, calling its Elixir APIs directly without HTTP overhead.

## Layers

```
+------------------+
|  Browser (JS)    |  D3.js hooks, CodeMirror, Cytoscape.js
+------------------+
         |
+------------------+
| Phoenix LiveView |  DashboardLive, GraphLive, ChatLive, ...
+------------------+
         |
+--------+---------+
|  Rageg.Stats     |  GenServer polling Ragex/dllb, broadcasts PubSub
+------------------+
         |
+--------+---------+----------+
| Ragex (in-BEAM)  | Dllb TCP |  Knowledge graph, vector store, AI, analysis
+------------------+----------+
         |
+------------------+
| dllb Server      |  Rust: redb, Tantivy, HNSW, joerl actors
+------------------+
```

## Data Flow

### Real-time Updates

1. `Rageg.Stats` (GenServer) polls Ragex and dllb every 3 seconds.
2. Each poll produces a `snapshot` map with graph, embeddings, cache, AI, and
   dllb health metrics.
3. The snapshot is broadcast on the `"stats"` PubSub topic.
4. `DashboardLive` (and future LiveViews) subscribe to PubSub on mount.
5. On receiving `{:stats_updated, snapshot}`, LiveViews update their assigns,
   triggering a re-render pushed over the WebSocket.

### Client-side Visualizations

Heavy visualizations (force-directed graphs, treemaps, scatter plots) use
LiveView hooks:

1. LiveView computes data server-side (e.g. `Ragex.Graph.Algorithms.export_d3_json/1`).
2. Data is pushed to the JS hook via `push_event/3`.
3. The hook renders using D3.js / Cytoscape.js / CodeMirror.
4. User interactions in JS call back via `pushEvent` to trigger server handlers.

## Supervision Tree

```
Rageg.Supervisor (one_for_one)
  |-- RagegWeb.Telemetry
  |-- DNSCluster
  |-- Phoenix.PubSub (name: Rageg.PubSub)
  |-- Rageg.Stats (GenServer, polls every 3s)
  |-- RagegWeb.Endpoint (Bandit HTTP + LiveView WebSocket)
```

## Routing

All pages are LiveViews. The router defines routes grouped by phase:

- Phase 1: `/` (Dashboard)
- Phase 2: `/graph` (Knowledge Graph Explorer)
- Phase 3: `/quality`, `/dependencies`
- Phase 4: `/chat`, `/audit`
- Phase 5: `/refactor`, `/impact`
- Phase 6: `/embeddings`
- Phase 7: `/dllb`, `/dllb/actors`, `/dllb/storage`, `/dllb/graph`,
  `/dllb/vectors`, `/dllb/search`, `/dllb/code-intel`
- Phase 8: `/analyze`

## Theming

Uses DaisyUI with two themes (light/dark) defined in `assets/css/app.css`.
Theme selection respects `prefers-color-scheme` by default and can be
toggled manually. The choice is persisted in `localStorage`.

## Internationalization

All user-facing strings go through Gettext. Three locales are supported:

- `en` (English, default)
- `es` (Spanish)
- `ca` (Catalan)

The `RagegWeb.Plugs.Locale` plug reads locale from: query param > session >
Accept-Language header > default.

## Dependencies on Ragex

Rageg depends on Ragex as a path dependency (same umbrella). Key APIs used:

- `Ragex.stats/0` -- graph node/edge counts
- `Ragex.VectorStore.stats/0` -- embedding model info
- `Ragex.AI.Cache.stats/0` -- AI response cache metrics
- `Ragex.AI.Usage.all_stats/0` -- per-provider usage and cost
- `Ragex.Graph.Algorithms.export_d3_json/1` -- D3.js graph data (Phase 2)
- `Ragex.Graph.Algorithms.detect_communities/1` -- community detection (Phase 2)
- `Ragex.Analysis.Runner.run_all/1` -- full analysis pipeline (Phase 3+)
- `Ragex.Editor.Refactor.*` -- semantic refactoring (Phase 5)
- `Ragex.Agent.Core.*` -- RAG chat agent (Phase 4)

## Phase 2: Knowledge Graph Explorer

The graph explorer is the most complex client-server interaction:

1. `GraphLive.mount/3` sends `:load_graph` to itself on connect
2. `handle_info(:load_graph)` calls `Rageg.Graph.fetch_d3_data/1`
3. `Rageg.Graph` calls `Ragex.Graph.Algorithms.export_d3_json/1`, enriches
   nodes with betweenness centrality, computes community hulls
4. The enriched `%{nodes, links, communities, stats}` map is pushed to the
   client via `push_event("graph_data", data)`
5. `GraphHook` (D3.js) receives the data and builds the force simulation
6. User clicks a node -> `pushEvent("node_selected", {node_id: ...})`
7. Server calls `Rageg.Graph.node_details/1` -> assigns `selected_node`
8. Detail panel re-renders server-side with callers/callees

Metric changes are handled client-side only (no server round-trip) since
all metrics are pre-computed in the initial data push.

## Dependencies on dllb

- `Dllb.query/1` -- raw query execution for health checks
- `Dllb.MetaAST.ingest_tree/3` -- MetaAST visualization (Phase 7)
- `Dllb.Schema.bootstrap/1` -- schema introspection (Phase 7)
