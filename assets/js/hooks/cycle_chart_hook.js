/**
 * CycleChartHook -- D3.js force-directed graph for interactive circular dependency maps.
 */
function createCycleChartHook() {
  return {
    mounted() {
      this.handleEvent("circular_cycles", ({ cycles }) => this.renderChart(cycles));

      this.container = this.el;
      this.width = this.container.clientWidth || 500;
      this.height = this.container.clientHeight || 320;

      // Clean container on mount
      this.container.innerHTML = "";

      this.svg = d3.select(this.container)
        .append("svg")
        .attr("width", "100%")
        .attr("height", "100%")
        .attr("viewBox", `0 0 ${this.width} ${this.height}`);

      // Add marker definition for directed arrowheads
      this.svg.append("defs").append("marker")
        .attr("id", "cycle-arrowhead")
        .attr("viewBox", "0 -5 10 10")
        .attr("refX", 18) // position offset from node center
        .attr("refY", 0)
        .attr("markerWidth", 6)
        .attr("markerHeight", 6)
        .attr("orient", "auto")
        .append("path")
        .attr("d", "M0,-5L10,0L0,5")
        .attr("fill", "oklch(var(--er))");

      this.zoomGroup = this.svg.append("g");
      this.linkLayer = this.zoomGroup.append("g").attr("class", "links");
      this.nodeLayer = this.zoomGroup.append("g").attr("class", "nodes");

      const zoom = d3.zoom()
        .scaleExtent([0.3, 5])
        .on("zoom", (event) => this.zoomGroup.attr("transform", event.transform));
      this.svg.call(zoom);

      this.resizeObserver = new ResizeObserver(() => {
        this.width = this.container.clientWidth || 500;
        this.height = this.container.clientHeight || 320;
        this.svg.attr("viewBox", `0 0 ${this.width} ${this.height}`);
      });
      this.resizeObserver.observe(this.container);
    },

    destroyed() {
      if (this.resizeObserver) this.resizeObserver.disconnect();
    },

    renderChart(cycles) {
      if (!cycles || cycles.length === 0) {
        this.zoomGroup.selectAll("*").remove();
        return;
      }

      // 1. Build nodes and links
      const nodeSet = new Set();
      const links = [];

      cycles.forEach((cycle, cycleIdx) => {
        for (let i = 0; i < cycle.length; i++) {
          const source = cycle[i];
          const target = cycle[(i + 1) % cycle.length];
          nodeSet.add(source);
          nodeSet.add(target);

          links.push({
            source,
            target,
            cycleIdx
          });
        }
      });

      const nodes = Array.from(nodeSet).map(id => ({ id }));

      // 2. Setup simulation
      const simulation = d3.forceSimulation(nodes)
        .force("link", d3.forceLink(links).id(d => d.id).distance(120))
        .force("charge", d3.forceManyBody().strength(-200))
        .force("center", d3.forceCenter(this.width / 2, this.height / 2))
        .force("collision", d3.forceCollide().radius(40));

      // 3. Render links
      const link = this.linkLayer.selectAll("line")
        .data(links)
        .join("line")
        .attr("stroke", "oklch(var(--er) / 0.5)")
        .attr("stroke-width", 2)
        .attr("marker-end", "url(#cycle-arrowhead)");

      // 4. Render nodes
      const node = this.nodeLayer.selectAll("g")
        .data(nodes)
        .join("g")
        .attr("cursor", "grab")
        .call(d3.drag()
          .on("start", dragstarted)
          .on("drag", dragged)
          .on("end", dragended));

      node.append("circle")
        .attr("r", 8)
        .attr("fill", "oklch(var(--er))")
        .attr("stroke", "oklch(var(--b1))")
        .attr("stroke-width", 2);

      node.append("text")
        .attr("dy", -12)
        .attr("text-anchor", "middle")
        .attr("fill", "oklch(var(--bc))")
        .style("font-size", "10px")
        .style("font-family", "monospace")
        .text(d => d.id.split(".").pop());

      // Hover interaction to highlight cycle
      node.on("mouseenter", (event, d) => {
        const nodeCycles = links.filter(l => l.source.id === d.id || l.target.id === d.id).map(l => l.cycleIdx);
        const cycleSet = new Set(nodeCycles);

        link.attr("stroke", l => cycleSet.has(l.cycleIdx) ? "oklch(var(--er))" : "oklch(var(--bc) / 0.1)")
          .attr("stroke-width", l => cycleSet.has(l.cycleIdx) ? 3 : 1);

        node.selectAll("circle")
          .attr("fill", n => {
            const participates = links.some(l => cycleSet.has(l.cycleIdx) && (l.source.id === n.id || l.target.id === n.id));
            return participates ? "oklch(var(--er))" : "oklch(var(--bc) / 0.3)";
          });
      });

      node.on("mouseleave", () => {
        link.attr("stroke", "oklch(var(--er) / 0.5)")
          .attr("stroke-width", 2);
        node.selectAll("circle").attr("fill", "oklch(var(--er))");
      });

      simulation.on("tick", () => {
        link
          .attr("x1", d => d.source.x)
          .attr("y1", d => d.source.y)
          .attr("x2", d => d.target.x)
          .attr("y2", d => d.target.y);

        node
          .attr("transform", d => `translate(${d.x},${d.y})`);
      });

      function dragstarted(event, d) {
        if (!event.active) simulation.alphaTarget(0.3).restart();
        d.fx = d.x;
        d.fy = d.y;
      }

      function dragged(event, d) {
        d.fx = event.x;
        d.fy = event.y;
      }

      function dragended(event, d) {
        if (!event.active) simulation.alphaTarget(0);
        d.fx = null;
        d.fy = null;
      }
    }
  };
}

export default createCycleChartHook;
