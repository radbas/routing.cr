# The outcome of `Router#match`.
#
# Exactly one of three cases applies:
# - found: `#match?` is `true` and `#handler` is set
# - method not allowed: `#allowed_methods` lists the methods the path accepts
# - not found: neither
struct Radbas::Routing::Result(T)
  # The matched handler, or `nil` if nothing matched.
  getter handler : T?

  def initialize(
    @handler : T? = nil,
    @params : Hash(String, String)? = nil,
    @allowed_methods : Array(String)? = nil,
  )
  end

  # Whether a handler matched.
  def match? : Bool
    !@handler.nil?
  end

  # Values captured by the route's params, keyed by param name.
  # Values are percent-decoded and may not be valid UTF-8.
  def params : Hash(String, String)
    # allocated lazily, most matches capture nothing
    @params || {} of String => String
  end

  # Methods the path accepts if it matched but the method did not, for the `Allow` header of a 405 response.
  def allowed_methods : Array(String)
    @allowed_methods || [] of String
  end
end
