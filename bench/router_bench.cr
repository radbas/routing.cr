# crystal run --release bench/router_bench.cr
require "benchmark"
require "../src/radbas-routing"

router = Radbas::Routing::Router(Int32).new

%w[users posts comments tags orders products invoices teams projects events].each_with_index do |resource, i|
  router.map(["GET", "POST"], "/api/#{resource}", i)
  router.map("GET", "/api/#{resource}/search", i)
  router.map(["GET", "PUT", "DELETE"], "/api/#{resource}/:id:d", i)
  router.map("GET", "/api/#{resource}/:id:d/history", i)
end
router.map("GET", "/", 100)
router.map("GET", "/about/contact", 101)
router.map("GET", "/static/*path", 102)

# more distinct paths than any route cache can hold
ids = (1..2000).map { |i| "/api/orders/#{i}/history" }
index = 0

Benchmark.ips do |x|
  x.report("static") { router.match("GET", "/api/projects/search") }
  x.report("dynamic") { router.match("GET", "/api/orders/42/history") }
  x.report("dynamic (2000 paths)") { router.match("GET", ids[index = (index + 1) % ids.size]) }
  x.report("percent-encoded") { router.match("GET", "/static/a%20b.css") }
  x.report("catchall") { router.match("GET", "/static/css/app/main.css") }
  x.report("not found") { router.match("GET", "/api/unknown/42") }
  x.report("method not allowed") { router.match("PATCH", "/api/orders/42") }
end
