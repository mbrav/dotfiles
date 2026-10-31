---
name: grafana-v2-dashboards
description: Build, restructure or improve Grafana v2 (dashboard.grafana.app/v2, Grafana 12+/13) dashboards through the Grafana MCP.
---

# Grafana v2 dashboards

How to build and change dashboards stored in Grafana's v2 schema (Grafana 12+), working only through the Grafana MCP.
The shape it aims for: sections with their own selectors, per-entity repeat rows and Inferno heatmaps. If the
project already has a dashboard in that style, read it first and copy its structure.

## Workflow

1. **Read what's live, not what's local.** A scratch copy is stale after any later save. Get the live
   state compactly with `grafana_api_request` plus a jq filter, not the whole JSON:

   ```
   GET /apis/dashboard.grafana.app/v2/namespaces/default/dashboards/<uid>
   jq: {gen: .metadata.generation, el: (.spec.elements|to_entries|map({k:.key,t:.value.spec.title,q:[.value.spec.data.spec.queries[]?.spec.query.spec.expr]}))}
   ```

   Row tree: `[.spec.layout.spec.rows[] | {t:.spec.title, vars:[.spec.variables[]?.spec.name], sub:[.spec.layout.spec.rows[]? | {t:.spec.title, rep:.spec.repeat.value}]}]`
2. **Discover metrics before designing.** Use `query_prometheus` with `count by(__name__) ({__name__=~"..._bucket"})`
   to find histograms (heatmap candidates). Use `count by(<label>)(...)` to size any repeat: about 15 values
   at most for collapsed repeat rows. Check which labels actually exist; for example, Alloy metrics have
   `pod` but no `node`, so the node is joined via `kube_pod_info`.
3. **Generate with a script, don't hand-edit JSON.** Write a Python builder in the scratchpad
   (helpers below) that loads the base JSON, mutates it and writes the result. This keeps it reproducible.
4. **Validate every query through the Grafana MCP** before saving, with `query_prometheus` against the
   datasource the panel uses (`list_datasources` gives the uids).
   Grafana doesn't expand dashboard variables here, so substitute them first: `$__rate_interval` and
   `$__interval` → `5m`, `$__range` → `6h`, global vars → a real value (`$namespace` → `prometheus`), and
   any other `$var` → `.*` (or a concrete value to test a repeat row). Run each as an instant query
   (`queryType: "instant"`); heatmap queries too, since only the result's presence matters.
   A result = OK. `EMPTY` is fine only for `> 0`-filtered drop/error panels; anything else empty means a
   wrong metric or label. Loki panels: same check with `query_loki_logs` / `query_loki_stats`.
   Several independent queries go out as parallel tool calls in one turn. For 50+ queries, batch ~20 into one
   instant query: `label_replace(count(<q1>), "k", "<key1>", "", "") or label_replace(count(<q2>), "k", "<key2>", "", "") or ...`;
   keys missing from the result are the empty ones. Check metric existence first with one
   `count by(__name__) ({__name__=~"a|b|c"})`.
5. **Save as small patches.** `diff_ops.py` turns old/new JSON into leaf-level patch ops plus one `$.layout`
   replace. Send elements and layout as two `update_dashboard` calls with a commit `message`.
   A full-body save of a ~120 KB dashboard is expensive; patches cut it to about a third.
6. **Verify.** Re-fetch the row tree (section vars and `repeat` must survive the save). Then
   `get_panel_image` the whole dashboard (width 1600, height 2400-3600, timeout 120) and look at it.

## Structure conventions

### Layout

- Top level is a `RowsLayout`. The first row is **Overview**: 6-8 stat tiles, `width 3-4, height 4`.
- Grid is 24 wide. Use timeseries at `8x8` (3 per line) or `12x8`, full-width heatmaps at `24x8`, and stats at `3x4`.
- A section that needs drill-down becomes a **nested RowsLayout**: an "All X" child row (aggregate view,
  expanded) followed by a child row titled `$x`, with `repeat: {mode: "variable", value: "x"}`, `collapse: true`.
- Collapse low-traffic sections (Resources, Canary, Rings) at the top level.
- Every panel gets a `description` that says what bad looks like and which setting to tune.

### Variables: global only if almost every panel uses them

- **Global** (`spec.variables`): datasource(s) and the identity filters every query uses (namespace, job/component, pod).
- **Section-scoped** (`row.spec.variables`) for everything else: tenant, route, percentile, node, log level, free-text
  filter. They render as a selector bar inside the section, and child rows can repeat on them. Section vars may
  reference global vars (`$namespace`, `$job`).
- Repeating a child row on a **global** multi var (e.g. `$job` for per-component Resources) also works.
- Percentile selector, one per section that has latency panels (name it `<prefix>_q`):

  ```json
  {"kind":"CustomVariable","spec":{"name":"q_q","label":"Percentile","query":"P99 : 0.99,P90 : 0.9,P50 : 0.5,P99.9 : 0.999",
   "valuesFormat":"csv","current":{"text":"P99","value":"0.99"},"multi":false,"includeAll":false,"options":[],
   "hide":"dontHide","skipUrlSync":false,"allowCustomValue":true}}
  ```

  Use it as `histogram_quantile($q_q, ...)`, with legend and title `${q_q:text}`.
- Prefix section var names (`q_`, `lat_`, `a`) so they never collide across sections.
- Log sections get a `CustomVariable` level (multi) plus a `TextVariable` line filter:
  `|~ "level=(${log_level:pipe})" |~ "(?i)$log_filter"`.

### Panels

- Histograms come as a pair: a percentile timeseries (selector-driven) **and** a heatmap:

  ```
  expr: sum by(le) (rate(<metric>_bucket{...}[$__rate_interval]))
  query spec: "format":"heatmap", "instant":false, "range":true, legendFormat "{{le}}"
  vizConfig: {"kind":"VizConfig","group":"heatmap","version":"","spec":{"fieldConfig":{"defaults":{},"overrides":[]},
    "options":{"calculate":false,"cellGap":1,"filterValues":{"le":1e-09},"legend":{"show":true},
    "color":{"mode":"scheme","scheme":"Inferno","scale":"exponential","exponent":0.5,"steps":64},
    "tooltip":{"mode":"single","showColorScale":true,"yHistogram":true},"yAxis":{"unit":"s"}}}}
  ```

  Minimal options are enough; Grafana fills in the defaults.
- **VictoriaMetrics `vmrange` histograms** (`*_bucket{vmrange="lo...hi"}`, non-cumulative, no `le`) scraped into plain
  Prometheus: `histogram_quantile` returns nothing (that needs MetricsQL). For the heatmap, map the upper bound to `le` and
  skip the heatmap format, because the buckets are already per-range:
  `sum by(le) (label_replace(rate(m_bucket[$__rate_interval]), "le", "$1", "vmrange", ".*[.][.][.](.*)"))`, query
  format time_series, legend `{{le}}`, options `calculate:false, rowsFrame:{layout:"le"}`. For the timeseries
  use the mean `rate(m_sum)/rate(m_count)` instead of a percentile.
- **Converting a classic dashboard that is too big for one call:** delete it, create the v2 body with only the Overview
  elements and an Overview-only layout, then `add` `$.elements.<key>` ops one section at a time (orphan elements are
  accepted), and finish with one `$.layout` replace. Keep panel ids that alert annotations link to; numeric
  `viewPanel=<id>` deeplinks still resolve in v2.
- Limits are drawn as a second query `vector(<limit>)` with legend `limit...`, plus an override `byRegexp "limit.*"`
  that sets it dashed, red and with no fill. In a per-entity repeat row, a gauge works well:
  `max_over_time(sum(rate(x[$__rate_interval]))[$__range:]) / <limit>`, `percentunit`, green/orange 0.7/red 0.9.
- Container metrics per component: join on the app's build_info,
  `... * on(namespace, pod) group_left() max by(namespace, pod) (loki_build_info{job=~"$job"})`.
- Per-interval counts in bar panels: use `rate(...[$__rate_interval])`, **not** `increase(...[$__interval])`.
  The latter is empty when the interval is shorter than the scrape step.
- Drop/error panels: `... > 0` so a quiet panel stays empty. Stat totals: `or vector(0)`.
- Multi-value vars in matchers: `label=~"$var"`, which Grafana regex-joins. Inside a repeated row the var is single-valued.

### Cross-linking related dashboards

- Give related dashboards a shared tag (e.g. `loki-stack`), then add a top-bar link `{"type":"dashboards","tags":["loki-stack"],"keepTime":true,"asDropdown":false,"icon":"external link","title":"..."}`.
- Panel links to the sibling dashboard look like: `{"title":"...","url":"/d/<uid>/<slug>?${__url_time_range}"}`.

## v2 save gotchas (learned the hard way)

- **Check the stored schema first**: `GET /apis/dashboard.grafana.app/v2/.../<uid>` with jq `.status`. If you get
  `conversion.storedVersion: v0alpha1/v1*`, the dashboard is classic v1 and the v2 view is only a conversion. Patches on
  `$.elements` then fail ("field 'elements' is not an object"), and section vars and nested rows can't be stored.
  Grafana pins the stored version: neither the MCP nor a v2-API `PUT` can switch it in place. A `PUT` is silently
  down-converted, so never send a stripped layout as an intermediate step. To convert, take the `.spec` from the v2 GET,
  ask the user, then `DELETE /api/dashboards/uid/<uid>` and recreate it as v2 with the same uid and folder. Version history
  is lost (the old one goes to Recently deleted). Recovery from a bad save: `POST /api/dashboards/uid/<uid>/restore {"version": N}`.
- **Panels empty on short ranges but fine on 24h** = the datasource's Scrape interval (`jsonData.timeInterval`) is
  shorter than the real scrape interval, so `$__rate_interval` holds fewer than 2 samples. Check the real interval with
  `max(count_over_time(<metric>[10m]))` (10 = 60s, 20 = 30s) and fix the datasource, not the queries.
- A full body needs a top-level `"uid"`, or the save fails with `metadata.name required`.
- **Never omit empty lists.** `links`, `transformations`, `overrides`, variable `options`, `annotations` must be explicit `[]`.
  Omitted lists are stored as `null` and the page crashes with "Cannot read properties of null (reading 'map')".
  Keep the built-in annotation's `query.spec: {}`. Fix a crashed dashboard by re-saving the full body with `[]` everywhere;
  patching it fails.
- Patch paths are dotted with no brackets around keys: `$.elements.panel-x.spec.data.spec.queries[0].spec.query.spec.expr`,
  `$.layout`, `$.elements.<new>` (op `add`).
- Elements are keyed by name; give new ones readable ids (`q-hm`, `t-ingest`) and unique numeric `spec.id`s.
- A null threshold base `value` in `steps[0]` is normal, not a bug.
- Transformations are wrapped in v2: `{"kind":"Transformation","group":"organize","spec":{"options":{...}}}`. A classic
  `{"id":"organize","options":{...}}` is accepted but stored as `{"group":"","spec":{"options":null}}`, i.e. silently dropped.
- This MCP identity can't read the Grafana token; don't try to curl Grafana directly. Use the MCP only.

## Files here

- `diff_ops.py <old.json> <new.json> <out-prefix>`: writes `<prefix>.el.ops.json` (leaf diffs of elements) and
  `<prefix>.lay.ops.json` (layout replace) for `update_dashboard`.
