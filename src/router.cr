require "uri"
require "./node"
require "./result"

class Radbas::Routing::Router(T)
  private alias Validator = Proc(String, Bool)

  MAX_CACHE_SIZE = 512

  @validators = {
    w: ->(s : String) : Bool {
      return false if s.empty?
      s.squeeze { |c| return false unless c.ascii_alphanumeric? || c == '_' }
      true
    },
    a: ->(s : String) : Bool {
      return false if s.empty?
      s.squeeze { |c| return false unless c.ascii_alphanumeric? }
      true
    },
    l: ->(s : String) : Bool {
      return false if s.empty?
      s.squeeze { |c| return false unless c.ascii_letter? }
      true
    },
    d: ->(s : String) : Bool {
      return false if s.empty?
      s.squeeze { |c| return false unless c.ascii_number? }
      true
    },
  }

  property base_path = ""

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
    "#{@base_path}#{parts.reverse.join("/")}"
  end

  def map(method : String, path : String, handler : T, name : Symbol? = nil) : self
    leaf = apply(@route_tree, tokenize(path))
    @node_handlers[leaf] ||= {} of String => T
    @node_handlers[leaf][method] = handler
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

    tokens = tokenize(path.lchop(@base_path))
    result = resolve(@route_tree, tokens, method, params, 0)

    @cached_routes.shift? unless @cached_routes.size < MAX_CACHE_SIZE
    @cached_routes[cache_key] = result
  end

  # ameba:disable Metrics/CyclomaticComplexity
  private def resolve(
    node : Node,
    tokens : Array(String),
    method : String,
    params : Hash(String, String),
    index : UInt32
  ) : Result(T)
    while index < tokens.size
      token = tokens[index]
      index += 1
      # static
      if next_node = node.static[token]?
        node = next_node
        next
      end

      allowed_methods = [] of String
      # dynamic
      node.dynamic.each_value do |d_node|
        next if d_node.validator && !d_node.validator.as(Validator).call(token)
        params[d_node.value] = token
        result = resolve(d_node, tokens, method, params, index)
        return result if result.match?
        allowed_methods.concat(result.methods)
        params.delete(d_node.value)
      end

      # catchall
      escape = false
      node.catchall.each_value do |c_node|
        next if c_node.validator && !c_node.validator.as(Validator).call(token)
        params[c_node.value] = "#{tokens.skip(index - 1).join("/")}"
        node = c_node
        escape = true
        break
      end

      break if escape
      return Result(T).new(methods: allowed_methods.uniq)
    end

    handlers = @node_handlers[node]?
    handler = handlers && handlers[method]?
    methods = !handler && handlers ? handlers.keys : [] of String

    Result(T).new(handler, methods, params)
  end
end
