require "./spec_helper"

describe Radbas::Routing do
  describe "#match" do
    it "matches static path" do
      router = Router.new
      router.map("GET", "/hello/world", 1)

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
      router.map("GET", "/hello/:name", 2)

      result = router.match("GET", "hello/john")
      result.match?.should eq true
      result.handler.should eq 2
      result.params.should eq({"name" => "john"})

      result = router.match("GET", "hello/john/")
      result.match?.should eq false
      result.handler.should eq nil
    end

    it "matches catchall path" do
      router = Router.new
      router.map("GET", "/hello/*all", 3)

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

    it "matches http request" do
      router = Router.new
      router.map("GET", "/hello/world", 4)
      request = HTTP::Request.new("GET", "/hello/world")

      result = router.match(request)
      result.match?.should eq true
      result.handler.should eq 4
    end
  end
end
