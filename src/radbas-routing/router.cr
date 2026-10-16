require "uri"
require "./error"
require "./node"
require "./result"

# Routes are matched in order of priority: static > dynamic > catchall.
# The router is read-only while matching; define all routes before serving requests.
class Radbas::Routing::Router(T)
  alias Validator = Proc(String, Bool)

  VALIDATORS = {
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
  @named_routes = {} of Symbol => Node(T)
  # Routes without params, keyed by their decoded path.
  @static_routes = {} of String => Node(T)

  def add_validator(name : String, &validator : String -> Bool) : self
    @validators[name] = validator
    self
  end

  def has?(name : Symbol) : Bool
    @named_routes.has_key?(name)
  end

  # `params` is anything indexable by param name, e.g. a `NamedTuple` or `Hash`.
  def build(name : Symbol, params = NamedTuple.new) : String
    node = @named_routes[name]? || raise Error.new("No route named #{name}")
    segments = [] of String
    while parent = node.parent
      segments << case node.type
      in .static?    then URI.encode_path_segment(node.value)
      in .dynamic?   then URI.encode_path_segment(param(params, node.value))
      in .catch_all? then URI.encode_path(param(params, node.value))
      end
      node = parent
    end
    "/#{segments.reverse!.join('/')}"
  end

  private def param(params, name : String) : String
    value = params[name]? || raise Error.new("No value given for param #{name}")
    value.to_s
  end

  def map(methods : Array(String), path : String, handler : T, name : Symbol? = nil) : self
    node = insert(path)
    if name
      existing = @named_routes[name]?
      raise Error.new("Route name #{name} is already used") if existing && !existing.same?(node)
      @named_routes[name] = node
    end
    handlers = node.handlers ||= {} of String => T
    methods.each { |method| handlers[method] = handler }
    self
  end

  private def insert(path : String) : Node(T)
    node = @root
    segments = path.lstrip('/').split('/')
    static = true
    segments.each_with_index do |segment, index|
      case segment[0]?
      when ':'
        static = false
        name, validator = parse_param(segment)
        child = node.dynamic.find { |dynamic| dynamic.value == name && dynamic.validator == validator }
        unless child
          child = Node(T).new(:dynamic, node, name, validator)
          node.dynamic << child
        end
        node = child
      when '*'
        static = false
        raise Error.new("Catchall must be the last segment: #{path}") unless index == segments.size - 1
        name, validator = parse_param(segment)
        if child = node.catchall
          unless child.value == name && child.validator == validator
            raise Error.new("Conflicting catchall #{segment}: #{path}")
          end
          node = child
        else
          node = node.catchall = Node(T).new(:catch_all, node, name, validator)
        end
      else
        value = decode(segment)
        node = node.static[value] ||= Node(T).new(:static, node, value)
      end
    end
    # decoded "%2F" must not collide with a real "/"
    @static_routes["/#{segments.join('/')}"] = node if static && !path.includes?('%')
    node
  end

  private def parse_param(segment : String) : {String, Validator?}
    name, _, validator_name = segment.lchop.partition(':')
    raise Error.new("Missing param name: #{segment}") if name.empty?
    return {name, nil} if validator_name.empty?
    validator = @validators[validator_name]? || raise Error.new("Validator #{validator_name} is not defined")
    {name, validator}
  end

  def match(request : HTTP::Request) : Result(T)
    match(request.method, request.path)
  end

  def match(method : String, path : String) : Result(T)
    if !path.includes?('%') && (node = @static_routes[path]?) && (found = handler(node, method))
      return Result(T).new(found[0])
    end

    params = {} of String => String
    methods = [] of String
    segments = path.split('/').map! { |segment| decode(segment) }
    # skip leading slashes without copying the path
    start = segments.index(&.presence) || segments.size - 1

    if found = resolve(@root, segments, start, method, params, methods)
      return Result(T).new(found[0], methods.clear, params)
    end

    # RFC 9110 9.3.2: GET implies HEAD
    methods << "HEAD" if methods.includes?("GET") && !methods.includes?("HEAD")
    Result(T).new(methods: methods)
  end

  # Returns the handler wrapped in a tuple, so a falsey `T` still counts as a match.
  # Params are only written once a match is certain.
  private def resolve(
    node : Node(T),
    segments : Array(String),
    index : Int32,
    method : String,
    params : Hash(String, String),
    methods : Array(String),
  ) : Tuple(T)?
    unless segment = segments[index]?
      found = handler(node, method)
      if !found && (handlers = node.handlers)
        handlers.each_key { |key| methods << key unless methods.includes?(key) }
      end
      return found
    end

    if child = node.static[segment]?
      found = resolve(child, segments, index + 1, method, params, methods)
      return found if found
    end

    node.dynamic.each do |dynamic|
      next unless dynamic.valid?(segment)
      if found = resolve(dynamic, segments, index + 1, method, params, methods)
        params[dynamic.value] = segment
        return found
      end
    end

    return unless catchall = node.catchall
    value = segments[index..].join('/')
    return unless catchall.valid?(value)
    return unless found = resolve(catchall, segments, segments.size, method, params, methods)
    params[catchall.value] = value
    found
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
