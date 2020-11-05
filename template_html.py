import http.server # Our http server handler for http requests
import socketserver # Establish the TCP Socket connections
import glob
import sys

begin ='''
<!DOCTYPE html>
<meta charset="utf-8">
<style>

  .node circle {
      fill: #fff;
      stroke: steelblue;
      stroke-width: 1.5px;
  }

  .node {
      font: 10px sans-serif;
  }

  .link {
      fill: none;
      stroke: #ccc;
      stroke-width: 1.5px;
  }

</style>
<body>
  <script src="//d3js.org/d3.v3.min.js"></script>
  <script>
    function draw_dendrogram(json){
        function elbow(d, i) {
            return "M" + d.source.y + "," + d.source.x
                + "V" + d.target.x + "H" + d.target.y;
        }
        function flatten(j, cnt){
            if(j.children.length == 0) return [1, cnt];
            else{
                var res = j.children.map((a) => flatten(a, cnt+1));
                var sum = res.map(r => r[0]).reduce((a,b) => a+b, 0);
                var max = res.map(r =>r[1]).reduce((a, b) => a>b? a:b, 0);

                return [sum, max];
            }
        }

        var r = flatten(json, 1);
        var len = r[0], depth = r[1];
        var width = depth * 220,
            height = len * 150;

        var cluster = d3.layout.cluster()
            .size([height, width - 160]);

        d3.select("svg").remove()
        var svg = d3.select("#dendrogram").append("svg")
            .attr("width", width)
            .attr("height", height)
            .append("g")
            .attr("transform", "translate(40,0)");

        var nodes = cluster.nodes(json);

        var link = svg.selectAll(".link")
            .data(cluster.links(nodes))
            .enter().append("path")
            .attr("class", "link")
            .attr("d", elbow);

        var node = svg.selectAll(".node")
            .data(nodes)
            .enter().append("g")
            .attr("class", "node")
            .attr("transform", function(d) { return "translate(" + d.y + "," + d.x + ")"; })

        node.append("circle")
            .attr("r", 4.5);

        node.append("text")
            .attr("dx", function(d) { return d.children ? -8 : 8; })
            .attr("dy", function(d) { return d.children ? -7 : 3; })
            .attr("text-anchor", function(d) { return d.children ? "end" : "start"; })
            .text(function(d) { return d.name; })
            .on("click",function(d,i) { window.open("/"+d.name);});
            ;
    }

    function display(module) {
        var xmlhttp = new XMLHttpRequest();
        xmlhttp.onreadystatechange = function() {
            if (this.readyState == 4 && this.status == 200) {
                var data = JSON.parse(this.responseText);
                draw_dendrogram(data);
            }
        };
        xmlhttp.open("GET", module, true); xmlhttp.send();
    }
  </script>
'''
end = '''
<div id="dendrogram"></div>
</body>
</html>
'''
'''
'''
 
class MyHttpRequestHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        with open('index.html', 'w') as fp:
            fp.write(begin)
            for datajs in glob.glob("*.templates"):
                print(datajs)
                fp.write(f'''<span><button onclick="display('{datajs}')";">{datajs.replace(".templates", "")}</button></span>''')
            fp.write(end)
        return http.server.SimpleHTTPRequestHandler.do_GET(self)
 
Handler = MyHttpRequestHandler
 
with socketserver.TCPServer(("", int(sys.argv[1])), Handler) as httpd:
    print("Http Server Serving at port", sys.argv[1])
    httpd.serve_forever()
