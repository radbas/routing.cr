require "uri"
require "./error"
require "./node"
require "./result"

# Maps HTTP methods and paths to handlers of type `T`.
#
# Routes are matched in order of priority: static > dynamic > catchall.
# The router is read-only while matching; define all routes before serving requests.
#
# ```
# router = Radbas::Routing::Router(Int32).new
# router.map("GET", "/users/:id:d", 1, name: "user")
# router.match("GET", "/users/42").params # => {"id" => "42"}
# router.build("user", {id: 42})          # => "/users/42"
# ```
class Radbas::Routing::Router(T)
  # Decides whether a param value is acceptable.
  alias Validator = Proc(String, Bool)

  private alias Params = Hash(String, String)
  private alias Methods = Array(String)

  private SLASH   = '/'.ord.to_u8
  private PERCENT = '%'.ord.to_u8

  private VALIDATORS = {
    # word
    "w" => ->(str : String) { str.to_slice.all? { |byte| byte.chr.ascii_alphanumeric? || byte == '_'.ord } },
    # alphanumeric
    "a" => ->(str : String) { str.to_slice.all?(&.chr.ascii_alphanumeric?) },
    # letters
    "l" => ->(str : String) { str.to_slice.all?(&.chr.ascii_letter?) },
    # digits
    "d" => ->(str : String) { str.to_slice.all?(&.chr.ascii_number?) },
  }

  @validators : Hash(String, Validator) = VALIDATORS.dup
  @root = Node(T).new
  @named_routes = {} of String => Node(T)
  # Routes without params, keyed by their decoded path.
  @static_routes = {} of String => Node(T)

  def initialize
    {% if T.nilable? %}
      # a nil handler would be indistinguishable from no match
      {% raise "Router handler type must not be nilable, got #{T}" %}
    {% end %}
  end

  # Registers a validator usable in route params as `:param:name` or `*param:name`.
  # Built in: `w` (word characters), `a` (alphanumeric), `l` (letters), `d` (digits).
  #
  # Only affects routes mapped afterwards.
  def add_validator(name : String, &validator : String -> Bool) : self
    @validators[name] = validator
    self
  end

  # Whether a route with this name was mapped.
  def has?(name : String) : Bool
    @named_routes.has_key?(name)
  end

  # Builds the path of the route named *name*, percent-encoding all segments.
  #
  # *params* is anything indexable by param name, e.g. a `NamedTuple` or `Hash(String, _)`.
  # Raises `Error` if the route does not exist, or if a param is missing or rejected by its validator.
  def build(name : String, params = NamedTuple.new) : String
    node = @named_routes[name]? || raise Error.new("No route named #{name}")
    segments = [] of String
    while parent = node.parent
      segments << case node.type
      in .static?    then URI.encode_path_segment(node.value)
      in .dynamic?   then URI.encode_path_segment(param(params, node))
      in .catch_all? then URI.encode_path(param(params, node))
      end
      node = parent
    end
    "/#{segments.reverse!.join('/')}"
  end

  private def param(params, node : Node(T)) : String
    name = node.value
    value = params[name]? || raise Error.new("No value given for param #{name}")
    value = value.to_s
    raise Error.new("Invalid value for param #{name}: #{value.inspect}") unless node.valid?(value)
    value
  end

  # Maps *method* and *path* to *handler*. See `#map(methods, path, handler, name)`.
  def map(method : String, path : String, handler : T, *, name : String? = nil) : self
    map([method], path, handler, name: name)
  end

  # Maps each of *methods* and *path* to *handler*, optionally naming the route for `#build`.
  #
  # Mapping the same path again adds methods to the existing route.
  # Raises `Error` if the path is invalid or can never match, if a method is already mapped
  # for the path, or if *name* is used by another route. A rejected route changes nothing.
  def map(methods : Array(String), path : String, handler : T, *, name : String? = nil) : self
    raise Error.new("No methods given: #{path}") if methods.empty?
    # the leading slash is optional
    segments = path.lchop('/').split('/')
    validate(path, segments)
    node = find(path, segments)
    if name && (named = @named_routes[name]?) && !named.same?(node)
      raise Error.new("Route name #{name} is already used")
    end
    if (handlers = node.try(&.handlers)) && (taken = methods.find { |method| handlers.has_key?(method) })
      raise Error.new("Route #{taken} #{path} is already mapped")
    end

    node ||= insert(path, segments)
    @named_routes[name] = node if name
    handlers = node.handlers ||= {} of String => T
    methods.each { |method| handlers[method] = handler }
    self
  end

  # Returns the node of an existing route. Raises on a conflicting catchall.
  private def find(path : String, segments : Array(String)) : Node(T)?
    node = @root
    segments.each do |segment|
      case segment[0]?
      when ':'
        name, validator = parse_param(segment)
        node = node.dynamic.find { |dynamic| dynamic.value == name && dynamic.validator == validator }
      when '*'
        name, validator = parse_param(segment)
        node = node.catchall
        if node && !(node.value == name && node.validator == validator)
          raise Error.new("Conflicting catchall #{segment}: #{path}")
        end
      else
        node = node.static[decode(segment).to_slice]?
      end
      return unless node
    end
    node
  end

  private def insert(path : String, segments : Array(String)) : Node(T)
    node = @root
    segments.each do |segment|
      case segment[0]?
      when ':'
        name, validator = parse_param(segment)
        child = node.dynamic.find { |dynamic| dynamic.value == name && dynamic.validator == validator }
        unless child
          child = Node(T).new(:dynamic, node, name, validator)
          node.dynamic << child
        end
        node = child
      when '*'
        name, validator = parse_param(segment)
        # find ruled out a conflicting one
        node = node.catchall ||= Node(T).new(:catch_all, node, name, validator)
      else
        value = decode(segment)
        node = node.static[value.to_slice] ||= Node(T).new(:static, node, value)
      end
    end
    # decoded "%2F" must not collide with a real "/"
    if !path.includes?('%') && segments.none? { |segment| segment.starts_with?(':') || segment.starts_with?('*') }
      @static_routes["/#{segments.join('/')}"] = node
    end
    node
  end

  # Rejects what can never match, before the tree is touched.
  private def validate(path : String, segments : Array(String)) : Nil
    # request paths never contain them
    raise Error.new("Encode '?' and '#' as %3F and %23: #{path}") if path.includes?('?') || path.includes?('#')
    names = [] of String
    segments.each_with_index do |segment, index|
      next unless segment.starts_with?(':') || segment.starts_with?('*')
      if segment.starts_with?('*') && index != segments.size - 1
        raise Error.new("Catchall must be the last segment: #{path}")
      end
      name, _ = parse_param(segment)
      raise Error.new("Duplicate param #{name}: #{path}") if names.includes?(name)
      names << name
    end
  end

  private def parse_param(segment : String) : {String, Validator?}
    name, colon, validator_name = segment.lchop.partition(':')
    raise Error.new("Missing param name: #{segment}") if name.empty?
    return {name, nil} if colon.empty?
    validator = @validators[validator_name]? || raise Error.new("Validator #{validator_name.inspect} is not defined: #{segment}")
    {name, validator}
  end

  # Matches the request's method and path.
  def match(request : HTTP::Request) : Result(T)
    match(request.method, request.path)
  end

  # Matches *method* and the still percent-encoded *path*.
  #
  # `HEAD` falls back to the `GET` handler. Never mutates the router, so it is safe across threads.
  def match(method : String, path : String) : Result(T)
    # keys never contain '%', so encoded paths cannot hit
    if (node = @static_routes[path]?) && (found = handler(node, method))
      return Result(T).new(found[0])
    end

    # exactly one leading slash, so the router never sees a different path than a proxy in front of it
    return Result(T).new unless path.starts_with?('/')
    # "/" itself ends up at the empty segment
    found, params, methods = resolve(@root, path, 1, method, nil, nil)
    return Result(T).new(found[0], params) if found

    # RFC 9110 9.3.2: GET implies HEAD
    methods << "HEAD" if methods && methods.includes?("GET") && !methods.includes?("HEAD")
    Result(T).new(allowed_methods: methods)
  end

  # Matches the segment of *path* starting at byte *pos* (-1 past the end) against the children of *node*.
  #
  # Returns the handler wrapped in a tuple, so a falsey `T` still counts as a match.
  # Params are only written once a match is certain. Params and methods are allocated on first
  # write and passed back up, so matches without them allocate nothing.
  private def resolve(
    node : Node(T),
    path : String,
    pos : Int32,
    method : String,
    params : Params?,
    methods : Methods?,
  ) : {Tuple(T)?, Params?, Methods?}
    return resolve_end(node, method, params, methods) if pos < 0
    # the catchall decodes the whole rest itself
    return resolve_catchall(node, path, pos, method, params, methods) if node.static.empty? && node.dynamic.empty?
    resolve_segment(node, path, pos, method, params, methods)
  end

  private def resolve_segment(
    node : Node(T),
    path : String,
    pos : Int32,
    method : String,
    params : Params?,
    methods : Methods?,
  ) : {Tuple(T)?, Params?, Methods?}
    stop = path.byte_index(SLASH, pos) || path.bytesize
    next_pos = stop < path.bytesize ? stop + 1 : -1
    raw = path.to_slice[pos, stop - pos]
    decoded = URI.decode(path.byte_slice(pos, stop - pos)) if raw.includes?(PERCENT)

    if child = node.static[decoded.try(&.to_slice) || raw]?
      found, params, methods = resolve(child, path, next_pos, method, params, methods)
      return {found, params, methods} if found
    end

    unless node.dynamic.empty?
      segment = decoded || path.byte_slice(pos, stop - pos)
      found, params, methods = resolve_dynamic(node, segment, path, next_pos, method, params, methods)
      return {found, params, methods} if found
    end

    resolve_catchall(node, path, pos, method, params, methods)
  end

  private def resolve_end(node : Node(T), method : String, params : Params?, methods : Methods?) : {Tuple(T)?, Params?, Methods?}
    found = handler(node, method)
    if !found && (handlers = node.handlers)
      methods ||= Methods.new
      handlers.each_key { |key| methods << key unless methods.includes?(key) }
    end
    {found, params, methods}
  end

  private def resolve_dynamic(
    node : Node(T),
    segment : String,
    path : String,
    next_pos : Int32,
    method : String,
    params : Params?,
    methods : Methods?,
  ) : {Tuple(T)?, Params?, Methods?}
    node.dynamic.each do |dynamic|
      next unless dynamic.valid?(segment)
      found, params, methods = resolve(dynamic, path, next_pos, method, params, methods)
      next unless found
      params ||= Params.new
      params[dynamic.value] = segment
      return {found, params, methods}
    end
    {nil, params, methods}
  end

  private def resolve_catchall(
    node : Node(T),
    path : String,
    pos : Int32,
    method : String,
    params : Params?,
    methods : Methods?,
  ) : {Tuple(T)?, Params?, Methods?}
    return {nil, params, methods} unless catchall = node.catchall
    value = decode(path.byte_slice(pos))
    return {nil, params, methods} unless catchall.valid?(value)
    found, params, methods = resolve(catchall, path, -1, method, params, methods)
    return {nil, params, methods} unless found
    params ||= Params.new
    params[catchall.value] = value
    {found, params, methods}
  end

  private def handler(node : Node(T), method : String) : Tuple(T)?
    return unless handlers = node.handlers
    handler = handlers.fetch(method) do
      return unless method == "HEAD" && handlers.has_key?("GET")
      handlers["GET"]
    end
    {handler}
  end

  private def decode(segment : String) : String
    segment.includes?('%') ? URI.decode(segment) : segment
  end
end
