/**
 * GraphHook -- D3.js force-directed graph visualization for the Knowledge Graph Explorer.
 *
 * Receives graph data from the LiveView via push_event("graph_data", payload)
 * and renders an interactive SVG with:
 *   - Force-directed layout with configurable strength
 *   - Zoom and pan (mouse wheel + drag on background)
 *   - Node coloring by metric (pagerank, betweenness, degree, community)
 *   - Node sizing proportional to selected metric
 *   - Edge thickness proportional to call weight
 *   - Community convex hulls as semi-transparent backgrounds
 *   - Minimap in the bottom-right corner
 *   - Click to select node (pushes "node_selected" to server)
 *   - Double-click to focus/zoom on node
 *   - Tooltip on hover
 *   - Export as SVG
 */

// D3 color scales
const COMMUNITY_COLORS = [
  "#4e79a7", "#f28e2b", "#e15759", "#76b7b2", "#59a14f",
  "#edc948", "#b07aa1", "#ff9da7", "#9c755f", "#bab0ac",
  "#86bcb6", "#8cd17d", "#b6992d", "#499894", "#e15759",
  "#f1ce63", "#a0cbe8", "#d37295", "#fabfd2", "#b6992d"
];

const METRIC_SCALES = {
  pagerank:    { domain: [0, 0.05], colorRange: ["#e8f4f8", "#1a5276"] },
  betweenness: { domain: [0, 0.5],  colorRange: ["#fef9e7", "#7d6608"] },
  degree:      { domain: [0, 20],   colorRange: ["#f0f3f4", "#1b4f72"] },
  community:   { domain: null,      colorRange: null } // uses categorical
};

function createGraphHook() {
  return {
    mounted() {
      this.graphData = null;
      this.selectedNodeId = null;
      this.metric = "pagerank";
      this.simulation = null;

      // Listen for server events
      this.handleEvent("graph_data", (payload) => this.renderGraph(payload));
      this.handleEvent("update_metric", ({ metric }) => this.updateMetric(metric));
      this.handleEvent("export_svg", () => this.exportSVG());
      this.handleEvent("highlight_node", ({ nodeId }) => this.highlightNode(nodeId));

      // Set up container
      this.container = this.el;
      this.width = this.container.clientWidth || 800;
      this.height = this.container.clientHeight || 600;

      // Create SVG
      this.svg = d3.select(this.container)
        .append("svg")
        .attr("width", "100%")
        .attr("height", "100%")
        .attr("viewBox", `0 0 ${this.width} ${this.height}`)
        .attr("class", "graph-svg");

      // Zoom group
      this.zoomGroup = this.svg.append("g").attr("class", "zoom-group");

      // Layers (order matters for z-index)
      this.hullLayer = this.zoomGroup.append("g").attr("class", "hull-layer");
      this.linkLayer = this.zoomGroup.append("g").attr("class", "link-layer");
      this.nodeLayer = this.zoomGroup.append("g").attr("class", "node-layer");
      this.labelLayer = this.zoomGroup.append("g").attr("class", "label-layer");

      // Tooltip
      this.tooltip = d3.select(this.container)
        .append("div")
        .attr("class", "graph-tooltip")
        .style("position", "absolute")
        .style("display", "none")
        .style("pointer-events", "none")
        .style("padding", "6px 10px")
        .style("border-radius", "6px")
        .style("font-size", "12px")
        .style("z-index", "100")
        .style("background", "oklch(var(--b2))")
        .style("color", "oklch(var(--bc))")
        .style("border", "1px solid oklch(var(--b3))")
        .style("box-shadow", "0 2px 8px rgba(0,0,0,0.15)");

      // Set up zoom behavior
      this.zoom = d3.zoom()
        .scaleExtent([0.1, 8])
        .on("zoom", (event) => {
          this.zoomGroup.attr("transform", event.transform);
          this.updateMinimap();
        });

      this.svg.call(this.zoom);

      // Minimap
      this.createMinimap();

      // Handle resize
      this.resizeObserver = new ResizeObserver(() => {
        this.width = this.container.clientWidth || 800;
        this.height = this.container.clientHeight || 600;
        this.svg.attr("viewBox", `0 0 ${this.width} ${this.height}`);
      });
      this.resizeObserver.observe(this.container);
    },

    destroyed() {
      if (this.simulation) this.simulation.stop();
      if (this.resizeObserver) this.resizeObserver.disconnect();
    },

    renderGraph(data) {
      this.graphData = data;
      if (!data.nodes || data.nodes.length === 0) {
        this.showEmptyState();
        return;
      }

      // Clear previous
      this.hullLayer.selectAll("*").remove();
      this.linkLayer.selectAll("*").remove();
      this.nodeLayer.selectAll("*").remove();
      this.labelLayer.selectAll("*").remove();
      if (this.simulation) this.simulation.stop();

      const nodes = data.nodes.map(d => ({...d}));
      const links = data.links.map(d => ({...d}));

      // Create simulation
      this.simulation = d3.forceSimulation(nodes)
        .force("link", d3.forceLink(links).id(d => d.id).distance(80).strength(0.3))
        .force("charge", d3.forceManyBody().strength(-120).distanceMax(300))
        .force("center", d3.forceCenter(this.width / 2, this.height / 2))
        .force("collision", d3.forceCollide().radius(d => this.nodeRadius(d) + 2))
        .alphaDecay(0.02);

      // Draw links
      const link = this.linkLayer.selectAll("line")
        .data(links)
        .join("line")
        .attr("class", "graph-link")
        .attr("stroke", "oklch(var(--bc) / 0.15)")
        .attr("stroke-width", d => Math.max(0.5, Math.min(4, (d.weight || 1) * 1.5)))
        .attr("marker-end", "url(#arrowhead)");

      // Arrow marker
      this.svg.selectAll("defs").remove();
      const defs = this.svg.append("defs");
      defs.append("marker")
        .attr("id", "arrowhead")
        .attr("viewBox", "0 -5 10 10")
        .attr("refX", 20)
        .attr("refY", 0)
        .attr("markerWidth", 6)
        .attr("markerHeight", 6)
        .attr("orient", "auto")
        .append("path")
        .attr("d", "M0,-5L10,0L0,5")
        .attr("fill", "oklch(var(--bc) / 0.2)");

      // Draw nodes
      const node = this.nodeLayer.selectAll("circle")
        .data(nodes)
        .join("circle")
        .attr("class", "graph-node")
        .attr("r", d => this.nodeRadius(d))
        .attr("fill", d => this.nodeColor(d))
        .attr("stroke", "oklch(var(--b1))")
        .attr("stroke-width", 1.5)
        .attr("cursor", "pointer")
        .on("click", (event, d) => {
          event.stopPropagation();
          this.selectNode(d);
        })
        .on("dblclick", (event, d) => {
          event.stopPropagation();
          this.focusNode(d);
        })
        .on("mouseenter", (event, d) => this.showTooltip(event, d))
        .on("mouseleave", () => this.hideTooltip())
        .call(this.drag(this.simulation));

      // Draw labels (only for larger nodes)
      const label = this.labelLayer.selectAll("text")
        .data(nodes.filter(d => this.nodeRadius(d) > 5))
        .join("text")
        .attr("class", "graph-label")
        .attr("text-anchor", "middle")
        .attr("dy", d => this.nodeRadius(d) + 12)
        .attr("font-size", "9px")
        .attr("fill", "oklch(var(--bc) / 0.7)")
        .attr("pointer-events", "none")
        .text(d => d.label || d.id);

      // Draw community hulls
      this.drawCommunityHulls(data.communities, nodes);

      // Store refs
      this._nodes = node;
      this._links = link;
      this._labels = label;
      this._nodeData = nodes;

      // Tick
      this.simulation.on("tick", () => {
        link
          .attr("x1", d => d.source.x)
          .attr("y1", d => d.source.y)
          .attr("x2", d => d.target.x)
          .attr("y2", d => d.target.y);

        node
          .attr("cx", d => d.x)
          .attr("cy", d => d.y);

        label
          .attr("x", d => d.x)
          .attr("y", d => d.y);

        // Update hulls every 5 ticks for performance
        if (this.simulation.alpha() > 0.01) {
          this._tickCount = (this._tickCount || 0) + 1;
          if (this._tickCount % 5 === 0) {
            this.drawCommunityHulls(data.communities, nodes);
          }
        }

        this.updateMinimap();
      });

      // Click on background to deselect
      this.svg.on("click", () => this.deselectNode());

      // Fit to view after settling
      setTimeout(() => this.fitToView(), 2000);
    },

    nodeRadius(d) {
      const val = this.metricValue(d);
      const base = d.type === "module" ? 8 : 5;
      return Math.max(3, Math.min(20, base + val * 60));
    },

    metricValue(d) {
      switch (this.metric) {
        case "pagerank": return d.pagerank || 0;
        case "betweenness": return d.betweenness || 0;
        case "degree": return (d.degree || 0) / 20;
        case "community": return 0.3;
        default: return d.pagerank || 0;
      }
    },

    nodeColor(d) {
      if (this.metric === "community") {
        const idx = d.community != null ? (typeof d.community === "number" ? d.community : hashStr(String(d.community))) : 0;
        return COMMUNITY_COLORS[Math.abs(idx) % COMMUNITY_COLORS.length];
      }

      const scale = METRIC_SCALES[this.metric] || METRIC_SCALES.pagerank;
      const val = this.metricValue(d);
      const t = Math.min(1, Math.max(0, (val - scale.domain[0]) / (scale.domain[1] - scale.domain[0])));
      return interpolateColor(scale.colorRange[0], scale.colorRange[1], t);
    },

    updateMetric(metric) {
      this.metric = metric;
      if (!this._nodes) return;

      this._nodes
        .transition().duration(400)
        .attr("r", d => this.nodeRadius(d))
        .attr("fill", d => this.nodeColor(d));

      if (this.graphData) {
        this.drawCommunityHulls(this.graphData.communities, this._nodeData);
      }
    },

    drawCommunityHulls(communities, nodes) {
      this.hullLayer.selectAll("path").remove();
      if (this.metric !== "community" || !communities) return;

      const nodeMap = new Map(nodes.map(n => [n.id, n]));

      Object.entries(communities).forEach(([communityId, memberIds], i) => {
        const points = memberIds
          .map(id => nodeMap.get(id))
          .filter(n => n && n.x != null && n.y != null)
          .map(n => [n.x, n.y]);

        if (points.length < 3) return;

        const hull = d3.polygonHull(points);
        if (!hull) return;

        // Pad the hull slightly
        const centroid = d3.polygonCentroid(hull);
        const padded = hull.map(([x, y]) => {
          const dx = x - centroid[0];
          const dy = y - centroid[1];
          const dist = Math.sqrt(dx * dx + dy * dy);
          const pad = 15;
          return [x + (dx / dist) * pad, y + (dy / dist) * pad];
        });

        const color = COMMUNITY_COLORS[i % COMMUNITY_COLORS.length];

        this.hullLayer.append("path")
          .datum(padded)
          .attr("d", d => `M${d.join("L")}Z`)
          .attr("fill", color)
          .attr("fill-opacity", 0.08)
          .attr("stroke", color)
          .attr("stroke-opacity", 0.25)
          .attr("stroke-width", 1.5)
          .attr("stroke-dasharray", "4,2");
      });
    },

    selectNode(d) {
      this.selectedNodeId = d.id;

      // Visual highlight
      this._nodes
        .attr("stroke-width", n => n.id === d.id ? 3 : 1.5)
        .attr("stroke", n => n.id === d.id ? "oklch(var(--p))" : "oklch(var(--b1))");

      // Highlight connected edges
      this._links
        .attr("stroke", l => (l.source.id === d.id || l.target.id === d.id)
          ? "oklch(var(--p) / 0.6)" : "oklch(var(--bc) / 0.15)")
        .attr("stroke-width", l => (l.source.id === d.id || l.target.id === d.id)
          ? 2.5 : Math.max(0.5, Math.min(4, (l.weight || 1) * 1.5)));

      // Push to server
      this.pushEvent("node_selected", { node_id: d.id });
    },

    deselectNode() {
      this.selectedNodeId = null;
      if (!this._nodes) return;

      this._nodes
        .attr("stroke-width", 1.5)
        .attr("stroke", "oklch(var(--b1))");

      this._links
        .attr("stroke", "oklch(var(--bc) / 0.15)")
        .attr("stroke-width", d => Math.max(0.5, Math.min(4, (d.weight || 1) * 1.5)));

      this.pushEvent("node_deselected", {});
    },

    highlightNode(nodeId) {
      if (!this._nodeData) return;
      const node = this._nodeData.find(n => n.id === nodeId);
      if (node) this.selectNode(node);
    },

    focusNode(d) {
      const transform = d3.zoomIdentity
        .translate(this.width / 2, this.height / 2)
        .scale(2)
        .translate(-d.x, -d.y);

      this.svg.transition().duration(500).call(this.zoom.transform, transform);
    },

    fitToView() {
      if (!this._nodeData || this._nodeData.length === 0) return;

      const xs = this._nodeData.map(d => d.x).filter(v => v != null);
      const ys = this._nodeData.map(d => d.y).filter(v => v != null);
      if (xs.length === 0) return;

      const minX = Math.min(...xs) - 50;
      const maxX = Math.max(...xs) + 50;
      const minY = Math.min(...ys) - 50;
      const maxY = Math.max(...ys) + 50;

      const dx = maxX - minX;
      const dy = maxY - minY;
      const scale = Math.min(this.width / dx, this.height / dy, 2) * 0.9;
      const cx = (minX + maxX) / 2;
      const cy = (minY + maxY) / 2;

      const transform = d3.zoomIdentity
        .translate(this.width / 2, this.height / 2)
        .scale(scale)
        .translate(-cx, -cy);

      this.svg.transition().duration(750).call(this.zoom.transform, transform);
    },

    showTooltip(event, d) {
      const metrics = [
        `PageRank: ${(d.pagerank || 0).toFixed(4)}`,
        `Degree: ${d.degree || 0}`,
        `Betweenness: ${(d.betweenness || 0).toFixed(4)}`
      ].join("<br/>");

      const displayName = d.label || d.id;
      this.tooltip
        .style("display", "block")
        .html(`<strong>${displayName}</strong><br/><span style="opacity:0.7">${d.type}</span><br/>${metrics}`)
        .style("left", `${event.offsetX + 12}px`)
        .style("top", `${event.offsetY - 10}px`);
    },

    hideTooltip() {
      this.tooltip.style("display", "none");
    },

    showEmptyState() {
      this.zoomGroup.selectAll("*").remove();
      this.zoomGroup.append("text")
        .attr("x", this.width / 2)
        .attr("y", this.height / 2)
        .attr("text-anchor", "middle")
        .attr("fill", "oklch(var(--bc) / 0.4)")
        .attr("font-size", "16px")
        .text("No graph data. Run an analysis first.");
    },

    drag(simulation) {
      return d3.drag()
        .on("start", (event, d) => {
          if (!event.active) simulation.alphaTarget(0.1).restart();
          d.fx = d.x;
          d.fy = d.y;
        })
        .on("drag", (event, d) => {
          d.fx = event.x;
          d.fy = event.y;
        })
        .on("end", (event, d) => {
          if (!event.active) simulation.alphaTarget(0);
          d.fx = null;
          d.fy = null;
        });
    },

    // -- Minimap --
    createMinimap() {
      const mmW = 150, mmH = 100;
      this.minimapSvg = d3.select(this.container)
        .append("svg")
        .attr("class", "graph-minimap")
        .attr("width", mmW)
        .attr("height", mmH)
        .style("position", "absolute")
        .style("bottom", "8px")
        .style("right", "8px")
        .style("border", "1px solid oklch(var(--b3))")
        .style("border-radius", "6px")
        .style("background", "oklch(var(--b2) / 0.8)")
        .style("pointer-events", "none");

      this.minimapGroup = this.minimapSvg.append("g");
      this.minimapViewport = this.minimapSvg.append("rect")
        .attr("fill", "none")
        .attr("stroke", "oklch(var(--p))")
        .attr("stroke-width", 1.5)
        .attr("rx", 2);
    },

    updateMinimap() {
      if (!this._nodeData || this._nodeData.length === 0) return;

      const mmW = 150, mmH = 100;
      const xs = this._nodeData.map(d => d.x).filter(v => v != null);
      const ys = this._nodeData.map(d => d.y).filter(v => v != null);
      if (xs.length === 0) return;

      const minX = Math.min(...xs) - 20;
      const maxX = Math.max(...xs) + 20;
      const minY = Math.min(...ys) - 20;
      const maxY = Math.max(...ys) + 20;
      const dx = maxX - minX || 1;
      const dy = maxY - minY || 1;
      const scale = Math.min(mmW / dx, mmH / dy);

      // Draw minimap dots
      this.minimapGroup.selectAll("circle").remove();
      this.minimapGroup.selectAll("circle")
        .data(this._nodeData)
        .join("circle")
        .attr("cx", d => (d.x - minX) * scale)
        .attr("cy", d => (d.y - minY) * scale)
        .attr("r", 1.5)
        .attr("fill", d => this.nodeColor(d));

      // Draw viewport rectangle
      const t = d3.zoomTransform(this.svg.node());
      const vx = (-t.x / t.k - minX) * scale;
      const vy = (-t.y / t.k - minY) * scale;
      const vw = (this.width / t.k) * scale;
      const vh = (this.height / t.k) * scale;

      this.minimapViewport
        .attr("x", vx).attr("y", vy)
        .attr("width", Math.max(4, vw)).attr("height", Math.max(4, vh));
    },

    exportSVG() {
      const svgEl = this.svg.node();
      const serializer = new XMLSerializer();
      const svgString = serializer.serializeToString(svgEl);
      const blob = new Blob([svgString], { type: "image/svg+xml" });
      const url = URL.createObjectURL(blob);

      const a = document.createElement("a");
      a.href = url;
      a.download = "knowledge-graph.svg";
      a.click();
      URL.revokeObjectURL(url);
    }
  };
}

// -- Utility functions --

function hashStr(str) {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash) + str.charCodeAt(i);
    hash |= 0;
  }
  return hash;
}

function interpolateColor(c1, c2, t) {
  // Simple hex interpolation
  const r1 = parseInt(c1.slice(1, 3), 16), g1 = parseInt(c1.slice(3, 5), 16), b1 = parseInt(c1.slice(5, 7), 16);
  const r2 = parseInt(c2.slice(1, 3), 16), g2 = parseInt(c2.slice(3, 5), 16), b2 = parseInt(c2.slice(5, 7), 16);
  const r = Math.round(r1 + (r2 - r1) * t);
  const g = Math.round(g1 + (g2 - g1) * t);
  const b = Math.round(b1 + (b2 - b1) * t);
  return `#${r.toString(16).padStart(2, "0")}${g.toString(16).padStart(2, "0")}${b.toString(16).padStart(2, "0")}`;
}

export default createGraphHook;
