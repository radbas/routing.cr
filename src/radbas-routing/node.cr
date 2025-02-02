class Radbas::Routing::Node(T)
  enum Type
    STATIC
    DYNAMIC
    CATCHALL
  end

  getter type, parent, value, validator, static, dynamic, catchall

  def initialize(
    @type : Type = Type::STATIC,
    @parent : Node(T)? = nil,
    @value : String = "",
    @validator : Proc(String, Bool)? = nil,
  )
    @static = {} of String => Node(T)
    @dynamic = {} of String => Node(T)
    @catchall = {} of String => Node(T)
  end
end
