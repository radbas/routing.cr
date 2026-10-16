# :nodoc:
class Radbas::Routing::Node(T)
  enum Type
    Static
    Dynamic
    CatchAll
  end

  getter type : Type
  getter parent : Node(T)?
  getter value : String
  getter validator : Proc(String, Bool)?
  # Keyed by the decoded segment's bytes, so a request path can be looked up without copying.
  getter static = {} of Bytes => Node(T)
  getter dynamic = [] of Node(T)
  property catchall : Node(T)?
  property handlers : Hash(String, T)?

  def initialize(
    @type : Type = :static,
    @parent : Node(T)? = nil,
    @value : String = "",
    @validator : Proc(String, Bool)? = nil,
  )
  end

  # Params never match empty values.
  def valid?(value : String) : Bool
    return false if value.empty?
    validator = @validator
    validator.nil? || validator.call(value)
  end
end
