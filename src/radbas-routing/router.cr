require "uri"
require "./node"
require "./result"

class Radbas::Routing::Router(T)
  private alias Validator = Proc(String, Bool)

  MAX_CACHE_SIZE = 1024

  @validators = {
    # word
    w: ->(s : String) : Bool {
      return false if s.empty?
      s.squeeze { |c| return false unless c.ascii_alphanumeric? || c == '_' }
      true
    },
    # alphanumeric
    a: ->(s : String) : Bool {
      return false if s.empty?
      s.squeeze { |c| return false unless c.ascii_alphanumeric? }
      true
    },
    # letters
    l: ->(s : String) : Bool {
      return false if s.empty?
      s.squeeze { |c| return false unless c.ascii_letter? }
      true
    },
    # digits
    d: ->(s : String) : Bool {
      return false if s.empty?
      s.squeeze { |c| return false unless c.ascii_number? }
      true
    },
  }

  def initialize
    @route_tree = Node(T).new
    @named_routes = {} of Symbol => Node(T)
    @cached_routes = {} of String => Result(T)
    @node_handlers = {} of Node(T) => Hash(String, T)
  end

  def set_validator(name : Symbol, validator : Validator) : self
    @validators[name] = validator
    self
  end

  def has?(route : Symbol) : Bool
    @named_routes.has_key?(route)
  end

  def build(route : Symbol, args : NamedTuple? = nil) : String
    node = @named_routes[route]?
    raise "no route with name < #{route} > found" unless node
    parts = [] of String
    while node
      value = node.value
      unless node.type == Node::Type::STATIC
        raise "no value given for placeholder < #{value} >" unless args.has_key?(value)
        value = args[value].to_s
      end
      if node.type == Node::Type::CATCHALL
        parts << URI.encode_path(value)
      else
        parts << URI.encode_path_segment(value)
      end
      node = node.parent
    end
    parts.reverse.join("/")
  end

  def map(methods : Array(String), path : String, handler : T, name : Symbol? = nil) : self
    leaf = apply(@route_tree, tokenize(path))
    @node_handlers[leaf] ||= {} of String => T
    methods.each { |m| @node_handlers[leaf][m] = handler }
    @named_routes[name] = leaf if name
    @cached_routes.clear
    self
  end

  private def apply(node : Node(T), tokens : Array(String)) : Node(T)
    tokens.each do |token|
      path = node.static
      type = Node::Type::STATIC
      value = token
      validator = nil

      if token.starts_with?(":") || token.starts_with?("*")
        is_catchall = token[0] == '*'
        token = token.lchop
        split = token.split(":", 2)
        if validator_name = split[1]?
          validator = @validators[validator_name]?
          raise "validator < #{validator_name} > is not defined" unless validator
        end
        return node.catchall[token] = Node(T).new(Node::Type::CATCHALL, node, split[0], validator) if is_catchall
        path = node.dynamic
        type = Node::Type::DYNAMIC
        value = split[0]
      end

      path[token] = Node(T).new(type, node, value, validator) unless path.has_key?(token)
      node = path[token]
    end
    node
  end

  def tokenize(path : String) : Array(String)
    path.lstrip("/").split("/").map(&->URI.decode(String))
  end

  def match(request : HTTP::Request) : Result(T)
    match(request.method, request.path)
  end

  def match(method : String, path : String, params = {} of String => String) : Result(T)
    method = "GET" if method == "HEAD"
    cache_key = "#{method}#{path}"

    if result = @cached_routes[cache_key]?
      return result
    end

    tokens = tokenize(path)
    result = resolve(@route_tree, tokens, method, params, 0, [] of String)

    @cached_routes.shift? unless @cached_routes.size < MAX_CACHE_SIZE
    @cached_routes[cache_key] = result
  end

  private def resolve(
    node : Node,
    tokens : Array(String),
    method : String,
    params : Hash(String, String),
    index : Int32,
    allowed_methods : Array(String)
  ) : Result(T)
    # end
    unless token = tokens[index]?
      handlers = @node_handlers[node]?
      handler = handlers && handlers[method]?
      methods = !handler && handlers ? handlers.keys : [] of String

      return Result(T).new(handler, methods, params)
    end

    # static
    if static_node = node.static[token]?
      return resolve(static_node, tokens, method, params, index + 1, allowed_methods)
    end

    # dynamic
    node.dynamic.each_value do |dynamic_node|
      next if dynamic_node.validator && !dynamic_node.validator.as(Validator).call(token)
      result = resolve(dynamic_node, tokens, method, params, index + 1, allowed_methods)
      if result.match?
        result.params[dynamic_node.value] = token
        return result
      end
      allowed_methods.concat(result.methods)
    end

    # catchall
    node.catchall.each_value do |catchall_node|
      next if catchall_node.validator && !catchall_node.validator.as(Validator).call(token)
      params[catchall_node.value] = "#{tokens.skip(index).join("/")}"
      return resolve(catchall_node, tokens, method, params, tokens.size, allowed_methods)
    end

    # token mismatch
    Result(T).new(methods: allowed_methods.uniq)
  end
end
