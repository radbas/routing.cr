struct Radbas::Routing::Result(T)
  getter handler, methods, params

  def initialize(
    @handler : T? = nil,
    @methods = [] of String,
    @params = {} of String => String
  )
  end

  def match? : Bool
    !!@handler
  end
end
