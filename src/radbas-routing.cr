require "./radbas-routing/router"

module Radbas::Routing
  VERSION = {{ `shards version #{__DIR__}`.chomp.stringify }}
end
