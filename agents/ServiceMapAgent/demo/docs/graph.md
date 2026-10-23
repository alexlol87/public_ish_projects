# System graph

Drawn from `data/*.yaml`, one file per mapped repository, every time the site is built. Click a service to see its
endpoints, what it calls and who calls it; click the background to reset. Drag to move, scroll to zoom.

<div id="graph-layers">
<label><input type="checkbox" value="Edge" checked> Edge</label>
<label><input type="checkbox" value="Domain" checked> Domain</label>
<label><input type="checkbox" value="Workers" checked> Workers</label>
</div>

<div class="graph-wrap">
<div id="service-graph"></div>
<div id="graph-panel"><p>Click a service.</p></div>
</div>

Legend: circles are services (purple Edge, blue Domain, green Workers), orange boxes Kafka topics, grey barrels
databases, red hexagons external systems. Solid arrows are HTTP calls (the number is how many endpoint-to-endpoint
calls), dashed arrows events, dotted lines a service's own database.
