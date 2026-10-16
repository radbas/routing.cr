require "./spec_helper"

describe Radbas::Routing::Router do
  describe "#match" do
    it "matches static path" do
      router = Router.new
      router.map(["GET"], "/hello/world", 1)

      result = router.match("GET", "/hello/world")
      result.should be_a Result
      result.match?.should be_true
      result.handler.should eq 1

      router.match("GET", "hello/world").match?.should be_false
      router.match("GET", "/hello/world/").match?.should be_false
    end

    it "matches root path" do
      router = Router.new
      router.map(["GET"], "/", 1)

      router.match("GET", "/").handler.should eq 1
    end

    it "matches dynamic path" do
      router = Router.new
      router.map(["GET"], "/hello/:name/:age:d", 2)

      result = router.match("GET", "/hello/john/22")
      result.handler.should eq 2
      result.params.should eq({"name" => "john", "age" => "22"})

      router.match("GET", "/hello/john/").match?.should be_false
      router.match("GET", "/hello/john/abc").match?.should be_false
    end

    it "does not match empty dynamic segment" do
      router = Router.new
      router.map(["GET"], "/hello/:name", 1)

      router.match("GET", "/hello/").match?.should be_false
    end

    it "matches catchall path" do
      router = Router.new
      router.map(["GET"], "/hello/*all", 3)

      router.match("GET", "/hello/world").params.should eq({"all" => "world"})
      router.match("GET", "/hello/world/").params.should eq({"all" => "world/"})
      router.match("GET", "/hello/world/1234").params.should eq({"all" => "world/1234"})
      router.match("GET", "/hello/").match?.should be_false
    end

    it "validates the whole catchall value" do
      router = Router.new
      router.add_validator("path", &.matches?(/\A\d+(\/\d+)*\z/))
      router.map(["GET"], "/n/*rest:path", 1)

      router.match("GET", "/n/1/2").params.should eq({"rest" => "1/2"})
      router.match("GET", "/n/1/abc").match?.should be_false
    end

    it "keeps handlers when mapping a catchall route twice" do
      router = Router.new
      router.map(["GET"], "/files/*path", 1)
      router.map(["POST"], "/files/*path", 2)

      router.match("GET", "/files/a/b").handler.should eq 1
      router.match("POST", "/files/a/b").handler.should eq 2
    end

    it "prefers static over dynamic and backtracks" do
      router = Router.new
      router.map(["GET"], "/:id", 1)
      router.map(["GET"], "/hello/test", 2)

      result = router.match("GET", "/abc")
      result.handler.should eq 1
      result.params.should eq({"id" => "abc"})

      router.match("GET", "/hello/test").handler.should eq 2

      result = router.match("GET", "/hello")
      result.handler.should eq 1
      result.params.should eq({"id" => "hello"})
    end

    it "does not leak params from failed branches" do
      router = Router.new
      router.map(["GET"], "/a/*rest", 1)
      router.map(["POST"], "/:id/foo", 2)

      result = router.match("POST", "/a/foo")
      result.handler.should eq 2
      result.params.should eq({"id" => "a"})
    end

    it "returns independent params per match" do
      router = Router.new
      router.map(["GET"], "/u/:id", 1)

      router.match("GET", "/u/1").params["injected"] = "x"
      router.match("GET", "/u/1").params.should eq({"id" => "1"})
    end

    it "decodes segments after splitting" do
      router = Router.new
      router.map(["GET"], "/a%2Fb", 1)
      router.map(["GET"], "/f/:name", 2)

      router.match("GET", "/a%2Fb").handler.should eq 1
      router.match("GET", "/a/b").match?.should be_false
      router.match("GET", "/f/x%20y").params.should eq({"name" => "x y"})
    end

    it "matches http request" do
      router = Router.new
      router.map(["GET"], "/hello/world", 4)

      router.match(HTTP::Request.new("GET", "/hello/world")).handler.should eq 4
    end

    it "falls back to GET for HEAD" do
      router = Router.new
      router.map(["GET"], "/get", 1)
      router.map(["GET"], "/head", 2)
      router.map(["HEAD"], "/head", 3)

      router.match("HEAD", "/get").handler.should eq 1
      router.match("HEAD", "/head").handler.should eq 3
    end

    it "provides allowed methods" do
      router = Router.new
      router.map(["GET"], "/hello", 2)
      router.map(["POST"], "/hello", 3)

      result = router.match("POST", "/hello")
      result.handler.should eq 3
      result.allowed_methods.should be_empty

      result = router.match("PUT", "/hello")
      result.match?.should be_false
      result.allowed_methods.should eq ["GET", "POST", "HEAD"]

      router.match("PUT", "/nope").allowed_methods.should be_empty
    end

    it "collects allowed methods across routes" do
      router = Router.new
      router.map(["GET"], "/a/b", 1)
      router.map(["PUT"], "/a/*rest", 2)

      router.match("DELETE", "/a/b").allowed_methods.should eq ["GET", "PUT", "HEAD"]
    end

    it "provides allowed methods when the static fast path misses the method" do
      router = Router.new
      router.map("GET", "/a", 1)

      result = router.match("PUT", "/a")
      result.match?.should be_false
      result.allowed_methods.should eq ["GET", "HEAD"]
    end

    it "allocates no params or methods on a plain match" do
      router = Router.new
      router.map("GET", "/a", 1)

      result = router.match("GET", "/a")
      result.params.should be_empty
      result.allowed_methods.should be_empty
    end

    it "requires exactly one leading slash" do
      router = Router.new
      router.map("GET", "/", 1)
      router.map("GET", "a", 2)
      router.map("GET", "/:id", 3)

      router.match("GET", "/").handler.should eq 1
      router.match("GET", "/a").handler.should eq 2
      router.match("GET", "").match?.should be_false
      router.match("GET", "//").match?.should be_false
      router.match("GET", "//a").match?.should be_false
      router.match("GET", "a").match?.should be_false
      router.match("GET", "x").match?.should be_false
    end

    it "matches further leading slashes as empty segments" do
      router = Router.new.map("GET", "//a", 1)

      router.match("GET", "//a").handler.should eq 1
      router.match("GET", "/a").match?.should be_false
    end

    it "treats trailing and double slashes as significant" do
      router = Router.new
      router.map("GET", "/a/b", 1)
      router.map("GET", "/c/", 2)

      router.match("GET", "/a/b/").match?.should be_false
      router.match("GET", "/a//b").match?.should be_false
      router.match("GET", "/c/").handler.should eq 2
      router.match("GET", "/c").match?.should be_false
    end

    it "matches percent-encoded static segments" do
      router = Router.new
      router.map("GET", "/A/b", 1)
      router.map("GET", "/c%20d", 2)

      router.match("GET", "/%41/b").handler.should eq 1
      router.match("GET", "/c d").handler.should eq 2
      router.match("GET", "/c%20d").handler.should eq 2
    end

    it "passes invalid percent-encoding and non UTF-8 values through" do
      router = Router.new
      router.map("GET", "/f/:name", 1)

      router.match("GET", "/f/%zz").params.should eq({"name" => "%zz"})
      router.match("GET", "/f/%FF").params["name"].valid_encoding?.should be_false
    end

    it "decodes catchall values" do
      router = Router.new
      router.map("GET", "/s/*path", 1)

      router.match("GET", "/s/a%20b/c%2Fd").params.should eq({"path" => "a b/c/d"})
    end

    it "matches falsey handlers" do
      router = Radbas::Routing::Router(Bool).new
      router.map("GET", "/a", false)
      router.map("GET", "/b/:id", false)

      router.match("GET", "/a").match?.should be_true
      router.match("GET", "/b/1").match?.should be_true
    end

    it "is safe to call concurrently" do
      router = Router.new
      router.map(["GET"], "/u/:id:d", 1)
      done = Channel(Bool).new

      10.times do |i|
        spawn do
          1000.times do |j|
            id = (i * 1000 + j).to_s
            result = router.match("GET", "/u/#{id}")
            done.send(false) unless result.params == {"id" => id}
          end
          done.send(true)
        end
      end

      10.times { done.receive.should be_true }
    end
  end

  describe "#map" do
    it "maps a single method" do
      router = Router.new.map("GET", "/a", 1, name: "a")

      router.match("GET", "/a").handler.should eq 1
      router.has?("a").should be_true
    end

    it "keeps validators per router" do
      router = Router.new.add_validator("d") { true }
      router.map("GET", "/a/:id:d", 1)
      other = Router.new.map("GET", "/a/:id:d", 1)

      router.match("GET", "/a/x").match?.should be_true
      other.match("GET", "/a/x").match?.should be_false
    end

    it "rejects segments after a catchall" do
      expect_raises(Radbas::Routing::Error) { Router.new.map(["GET"], "/x/*rest/edit", 1) }
    end

    it "rejects empty param names" do
      expect_raises(Radbas::Routing::Error) { Router.new.map(["GET"], "/:", 1) }
      expect_raises(Radbas::Routing::Error) { Router.new.map(["GET"], "/*", 1) }
    end

    it "rejects unknown validators" do
      expect_raises(Radbas::Routing::Error) { Router.new.map(["GET"], "/:id:nope", 1) }
      expect_raises(Radbas::Routing::Error) { Router.new.map(["GET"], "/:id:", 1) }
    end

    it "rejects duplicate param names" do
      expect_raises(Radbas::Routing::Error) { Router.new.map("GET", "/:id/x/:id", 1) }
      expect_raises(Radbas::Routing::Error) { Router.new.map("GET", "/:id/*id", 1) }
    end

    it "rejects routes that can never match" do
      expect_raises(Radbas::Routing::Error) { Router.new.map([] of String, "/a", 1) }
      expect_raises(Radbas::Routing::Error) { Router.new.map("GET", "/search?q", 1) }
      expect_raises(Radbas::Routing::Error) { Router.new.map("GET", "/a#b", 1) }
    end

    it "leaves no trace of rejected routes" do
      router = Router.new
      expect_raises(Radbas::Routing::Error) { router.map("GET", "/:a/x/:a", 1) }
      router.map("GET", "/:b/x/y", 2)
      router.map("GET", "/:a/x/:c", 3)

      # :b was mapped first, so it is tried first
      router.match("GET", "/1/x/y").params.should eq({"b" => "1"})
    end

    it "treats percent-encoded ':' and '*' as literals" do
      router = Router.new.map("GET", "/%3Aid/%2A", 1)

      router.match("GET", "/:id/*").handler.should eq 1
      router.match("GET", "/x/y").match?.should be_false
    end

    it "rejects conflicting catchalls" do
      router = Router.new.map(["GET"], "/x/*a", 1)
      expect_raises(Radbas::Routing::Error) { router.map(["GET"], "/x/*b", 1) }
    end

    it "rejects methods already mapped for a path" do
      router = Router.new.map(["GET", "POST"], "/a/:id", 1)

      expect_raises(Radbas::Routing::Error) { router.map(["PUT", "POST"], "a/:id", 2) }
      router.match("PUT", "/a/1").match?.should be_false
      router.map("PUT", "/a/:id", 3).match("PUT", "/a/1").handler.should eq 3
    end

    it "leaves no trace of a route rejected for its name" do
      router = Router.new.map("GET", "/a", 1, name: "a")

      expect_raises(Radbas::Routing::Error) { router.map("GET", "/:b/x", 2, name: "a") }
      router.map("GET", "/:c/y", 3)
      router.map("GET", "/:b/y", 4)

      # a leftover :b node would have been tried first
      router.match("GET", "/1/y").handler.should eq 3
    end

    it "rejects duplicate route names" do
      router = Router.new.map(["GET"], "/a", 1, name: "a")
      router.map(["POST"], "/a", 2, name: "a").has?("a").should be_true
      expect_raises(Radbas::Routing::Error) { router.map(["GET"], "/b", 1, name: "a") }
    end
  end

  describe "#build" do
    it "builds routes" do
      router = Router.new
      router.map(["GET"], "/", 1, name: "root")
      router.map(["GET"], "/a b", 1, name: "static")
      router.map(["GET"], "/users/:id:d", 1, name: "user")
      router.map(["GET"], "/files/*path", 1, name: "files")

      router.build("root").should eq "/"
      router.build("static").should eq "/a%20b"
      router.build("user", {id: 5}).should eq "/users/5"
      router.build("files", {"path" => "a/b c"}).should eq "/files/a/b%20c"
    end

    it "raises on unknown route or missing param" do
      router = Router.new.map(["GET"], "/users/:id", 1, name: "user")

      expect_raises(Radbas::Routing::Error) { router.build("nope") }
      expect_raises(Radbas::Routing::Error) { router.build("user") }
    end

    it "raises on params the route would not match" do
      router = Router.new
      router.map("GET", "/users/:id:d", 1, name: "user")
      router.map("GET", "/files/*path", 1, name: "files")

      expect_raises(Radbas::Routing::Error) { router.build("user", {id: "abc"}) }
      expect_raises(Radbas::Routing::Error) { router.build("user", {id: ""}) }
      expect_raises(Radbas::Routing::Error) { router.build("files", {path: ""}) }
    end

    it "builds paths that match their route" do
      router = Router.new
      router.map("GET", "/u/:name/*rest", 1, name: "u")

      path = router.build("u", {name: "a/b%", rest: "c d/e"})
      path.should eq "/u/a%2Fb%25/c%20d/e"
      router.match("GET", path).params.should eq({"name" => "a/b%", "rest" => "c d/e"})
    end
  end
end
