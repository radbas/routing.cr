require "spec"
require "http/request"
require "../src/radbas-routing"

alias Router = Radbas::Routing::Router(Int32)
alias Result = Radbas::Routing::Result(Int32)
