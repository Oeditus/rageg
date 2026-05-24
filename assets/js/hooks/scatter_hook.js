/**
 * ScatterHook -- D3.js scatter plot for embedding space visualization.
 *
 * Receives 2D-projected points from the LiveView and renders them as
 * an interactive scatter plot with:
 *   - Color by type (function/module) or module
 *   - Hover tooltip with entity details
 *   - Click to select (pushes "point_selected" to server)
 *   - Search highlight (highlighted IDs glow)
 *   - k-NN lines drawn from selected point to neighbors
 *   - Zoom and pan
 */

const TYPE_COLORS = {
  "function": "#4e79a7",
  "module": "#e15759",
};

function createScatterHook() {
  return {
    mounted() {
      this.handleEvent("scatter_data", (data) => this.renderScatter(data));
      this.handleEvent("highlight_search", ({ ids }) => this.highlightPoints(ids));
      this.handleEvent("show_neighbors", ({ source, neighbors }) => this.drawNeighborLines(source, neighbors));
      this.handleEvent("clear_highlights", () => this.clearHighlights());

      this.container = this.el;
      this.width = this.container.clientWidth || 600;
      this.height = this.container.clientHeight || 500;

      this.svg = d3.select(this.container)
        .append("svg")
        .attr("width", "100%")
        .attr("height", "100%")
        .attr("viewBox", `0 0 ${this.width} ${this.height}`);

      this.zoomGroup = this.svg.append("g");
      this.lineLayer = this.zoomGroup.append("g").attr("class", "line-layer");
      this.dotLayer = this.zoomGroup.append("g").attr("class", "dot-layer");

      this.tooltip = d3.select(this.container)
        .append("div")
        .style("position", "absolute")
        .style("display", "none")
        .style("pointer-events", "none")
        .style("padding", "4px 8px")
        .style("border-radius", "4px")
        .style("font-size", "11px")
        .style("z-index", "100")
        .style("background", "oklch(var(--b2))")
        .style("color", "oklch(var(--bc))")
        .style("border", "1px solid oklch(var(--b3))");

      const zoom = d3.zoom()
        .scaleExtent([0.5, 20])
        .on("zoom", (event) => this.zoomGroup.attr("transform", event.transform));
      this.svg.call(zoom);

      this.resizeObserver = new ResizeObserver(() => {
        this.width = this.container.clientWidth || 600;
        this.height = this.container.clientHeight || 500;
        this.svg.attr("viewBox", `0 0 ${this.width} ${this.height}`);
      });
      this.resizeObserver.observe(this.container);
    },

    destroyed() {
      if (this.resizeObserver) this.resizeObserver.disconnect();
    },

    renderScatter(data) {
      if (!data.points || data.points.length === 0) {
        this.zoomGroup.selectAll("*").remove();
        this.zoomGroup.append("text")
          .attr("x", this.width / 2).attr("y", this.height / 2)
          .attr("text-anchor", "middle")
          .attr("fill", "oklch(var(--bc) / 0.4)")
          .text("No embeddings. Run an analysis first.");
        return;
      }

      const points = data.points;
      const xs = points.map(p => p.x);
      const ys = points.map(p => p.y);
      const pad = 40;

      this.xScale = d3.scaleLinear()
        .domain([Math.min(...xs), Math.max(...xs)])
        .range([pad, this.width - pad]);

      this.yScale = d3.scaleLinear()
        .domain([Math.min(...ys), Math.max(...ys)])
        .range([this.height - pad, pad]);

      this.dotLayer.selectAll("*").remove();
      this.lineLayer.selectAll("*").remove();
      this._points = points;

      const dots = this.dotLayer.selectAll("circle")
        .data(points)
        .join("circle")
        .attr("cx", d => this.xScale(d.x))
        .attr("cy", d => this.yScale(d.y))
        .attr("r", d => d.type === "module" ? 5 : 3)
        .attr("fill", d => TYPE_COLORS[d.type] || "#999")
        .attr("fill-opacity", 0.7)
        .attr("stroke", "none")
        .attr("cursor", "pointer")
        .on("mouseenter", (event, d) => {
          this.tooltip
            .style("display", "block")
            .html(`<strong>${d.id}</strong><br/><span style="opacity:0.6">${d.type}</span>`)
            .style("left", `${event.offsetX + 10}px`)
            .style("top", `${event.offsetY - 10}px`);
        })
        .on("mouseleave", () => this.tooltip.style("display", "none"))
        .on("click", (event, d) => {
          event.stopPropagation();
          this.pushEvent("point_selected", { id: d.id });
        });

      this._dots = dots;
      this.svg.on("click", () => this.pushEvent("point_deselected", {}));
    },

    highlightPoints(ids) {
      if (!this._dots) return;
      const idSet = new Set(ids);

      this._dots
        .attr("r", d => idSet.has(d.id) ? 7 : (d.type === "module" ? 5 : 3))
        .attr("fill-opacity", d => idSet.has(d.id) ? 1.0 : 0.3)
        .attr("stroke", d => idSet.has(d.id) ? "oklch(var(--p))" : "none")
        .attr("stroke-width", d => idSet.has(d.id) ? 2 : 0);
    },

    drawNeighborLines(sourceId, neighborIds) {
      this.lineLayer.selectAll("*").remove();
      if (!this._points) return;

      const pointMap = new Map(this._points.map(p => [p.id, p]));
      const source = pointMap.get(sourceId);
      if (!source) return;

      neighborIds.forEach(nId => {
        const neighbor = pointMap.get(nId);
        if (!neighbor) return;

        this.lineLayer.append("line")
          .attr("x1", this.xScale(source.x))
          .attr("y1", this.yScale(source.y))
          .attr("x2", this.xScale(neighbor.x))
          .attr("y2", this.yScale(neighbor.y))
          .attr("stroke", "oklch(var(--p) / 0.5)")
          .attr("stroke-width", 1.5)
          .attr("stroke-dasharray", "4,2");
      });

      // Highlight the set
      const allIds = [sourceId, ...neighborIds];
      this.highlightPoints(allIds);
    },

    clearHighlights() {
      if (!this._dots) return;
      this._dots
        .attr("r", d => d.type === "module" ? 5 : 3)
        .attr("fill-opacity", 0.7)
        .attr("stroke", "none");
      this.lineLayer.selectAll("*").remove();
    }
  };
}

export default createScatterHook;
