/**
 * GraphLayoutWorker -- runs the D3 force simulation off the main thread.
 *
 * At ~1000 nodes the force simulation ticks hundreds of times and each tick
 * touches every node and link. Doing that on the main thread competes with
 * LiveView's DOM patching and makes the whole page feel janky. Running the
 * simulation here keeps the UI thread free: we only post back the settled
 * positions, which the hook applies in a single pass.
 *
 * Messages in:
 *   { type: "layout", nodes: [{id}], links: [{source, target, weight}],
 *     width, height, iterations }
 *
 * Messages out:
 *   { type: "layout_done", positions: [[id, x, y], ...] }
 *   { type: "layout_error", message }
 *
 * The D3 simulation is created with a no-op tick listener and stepped
 * manually so we never depend on requestAnimationFrame (unavailable in
 * workers) and can stop after a fixed number of iterations.
 */

import * as d3 from "d3"

self.onmessage = (event) => {
  const data = event.data || {}

  if (data.type !== "layout") return

  try {
    const { nodes, links, width, height } = data
    const iterations = data.iterations || 300

    if (!nodes || nodes.length === 0) {
      self.postMessage({ type: "layout_done", positions: [] })
      return
    }

    // Clone: d3 mutates the objects it is given.
    const simNodes = nodes.map((n) => ({ id: n.id }))
    const simLinks = links.map((l) => ({ source: l.source, target: l.target }))

    const simulation = d3
      .forceSimulation(simNodes)
      .force("link", d3.forceLink(simLinks).id((d) => d.id).distance(80).strength(0.3))
      .force("charge", d3.forceManyBody().strength(-120).distanceMax(300))
      .force("center", d3.forceCenter((width || 800) / 2, (height || 600) / 2))
      .force("collision", d3.forceCollide().radius(10))
      .alphaDecay(0.02)
      .stop()

    // Step synchronously; no ticks are painted from here.
    simulation.tick(iterations)

    const positions = simNodes.map((n) => [n.id, n.x || 0, n.y || 0])

    self.postMessage({ type: "layout_done", positions })
  } catch (error) {
    self.postMessage({ type: "layout_error", message: String(error) })
  }
}
