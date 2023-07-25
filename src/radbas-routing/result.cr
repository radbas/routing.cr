record Radbas::Routing::Result(T),
  handler : T? = nil,
  methods : Array(String) = [] of String,
  params : Hash(String, String) = {} of String => String do
  def match? : Bool
    !!@handler
  end
end
