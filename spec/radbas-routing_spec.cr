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

      router.match("GET", "hello/world").handler.should eq 1
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
      result.methods.should be_empty

      result = router.match("PUT", "/hello")
      result.match?.should be_false
      result.methods.should eq ["GET", "POST", "HEAD"]

      router.match("PUT", "/nope").methods.should be_empty
    end

    it "collects allowed methods across routes" do
      router = Router.new
      router.map(["GET"], "/a/b", 1)
      router.map(["PUT"], "/a/*rest", 2)

      router.match("DELETE", "/a/b").methods.should eq ["GET", "PUT", "HEAD"]
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
    it "rejects segments after a catchall" do
      expect_raises(Radbas::Routing::Error) { Router.new.map(["GET"], "/x/*rest/edit", 1) }
    end

    it "rejects empty param names" do
      expect_raises(Radbas::Routing::Error) { Router.new.map(["GET"], "/:", 1) }
      expect_raises(Radbas::Routing::Error) { Router.new.map(["GET"], "/*", 1) }
    end

    it "rejects unknown validators" do
      expect_raises(Radbas::Routing::Error) { Router.new.map(["GET"], "/:id:nope", 1) }
    end

    it "rejects conflicting catchalls" do
      router = Router.new.map(["GET"], "/x/*a", 1)
      expect_raises(Radbas::Routing::Error) { router.map(["GET"], "/x/*b", 1) }
    end

    it "rejects duplicate route names" do
      router = Router.new.map(["GET"], "/a", 1, :a)
      router.map(["POST"], "/a", 2, :a).has?(:a).should be_true
      expect_raises(Radbas::Routing::Error) { router.map(["GET"], "/b", 1, :a) }
    end
  end

  describe "#build" do
    it "builds routes" do
      router = Router.new
      router.map(["GET"], "/", 1, :root)
      router.map(["GET"], "/a b", 1, :static)
      router.map(["GET"], "/users/:id:d", 1, :user)
      router.map(["GET"], "/files/*path", 1, :files)

      router.build(:root).should eq "/"
      router.build(:static).should eq "/a%20b"
      router.build(:user, {id: 5}).should eq "/users/5"
      router.build(:files, {"path" => "a/b c"}).should eq "/files/a/b%20c"
    end

    it "raises on unknown route or missing param" do
      router = Router.new.map(["GET"], "/users/:id", 1, :user)

      expect_raises(Radbas::Routing::Error) { router.build(:nope) }
      expect_raises(Radbas::Routing::Error) { router.build(:user) }
    end
  end
end
