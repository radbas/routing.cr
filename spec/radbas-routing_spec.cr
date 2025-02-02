require "./spec_helper"

describe Radbas::Routing do
  describe "#match" do
    it "matches static path" do
      router = Router.new
      router.map(["GET"], "/hello/world", 1)

      result = router.match("GET", "hello/world")
      result.should be_a Result
      result.match?.should eq true
      result.handler.should eq 1

      result = router.match("GET", "hello/world/")
      result.match?.should eq false
      result.handler.should eq nil
    end

    it "matches dynamic path" do
      router = Router.new
      router.map(["GET"], "/hello/:name/:age:d", 2)

      result = router.match("GET", "hello/john/22")
      result.match?.should eq true
      result.handler.should eq 2
      result.params.should eq({"name" => "john", "age" => "22"})

      result = router.match("GET", "hello/john/")
      result.match?.should eq false
      result.handler.should eq nil
    end

    it "matches catchall path" do
      router = Router.new
      router.map(["GET"], "/hello/*all", 3)

      result = router.match("GET", "hello/world")
      result.match?.should eq true
      result.handler.should eq 3
      result.params.should eq({"all" => "world"})

      result = router.match("GET", "hello/world/")
      result.match?.should eq true
      result.params.should eq({"all" => "world/"})

      result = router.match("GET", "hello/world/1234")
      result.match?.should eq true
      result.params.should eq({"all" => "world/1234"})
    end

    it "matches dynamic and static path" do
      router = Router.new
      router.map(["GET"], "/:id", 1)
      router.map(["GET"], "/hello/test", 2)

      result = router.match("GET", "/abc")
      result.match?.should eq true
      result.handler.should eq 1
      result.params.should eq({"id" => "abc"})

      result = router.match("GET", "/hello/test")
      result.match?.should eq true
      result.handler.should eq 2

      result = router.match("GET", "/hello")
      result.match?.should eq true
      result.handler.should eq 1
      result.params.should eq({"id" => "hello"})
    end

    it "matches http request" do
      router = Router.new
      router.map(["GET"], "/hello/world", 4)
      request = HTTP::Request.new("GET", "/hello/world")

      result = router.match(request)
      result.match?.should eq true
      result.handler.should eq 4
    end

    it "provides allowed methods" do
      router = Router.new
      router.map(["GET"], "/hello", 2)

      result = router.match("GET", "hello")
      result.match?.should eq true
      result.handler.should eq 2
      result.methods.should eq([] of String)

      router.map(["POST"], "/hello", 3)

      result = router.match("POST", "hello")
      result.match?.should eq true
      result.handler.should eq 3
      result.methods.should eq([] of String)

      result = router.match("PUT", "hello")
      result.match?.should eq false
      result.handler.should eq nil
      result.methods.should eq ["GET", "POST"]
    end
  end
end
