# Routing.cr

Fast and simple HTTP router.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     radbas-routing:
       github: radbas/routing.cr
   ```

2. Run `shards install`

## Usage

```crystal
require "http"
require "radbas-routing"

alias Context = HTTP::Server::Context
alias Params = Hash(String, String)
alias Handler = Proc(Context, Params, Nil)

# create router
router = Radbas::Routing::Router(Handler).new

# define routes
router.map("GET", "/hello/:name", ->(context : Context, params : Params) {
  context.response.print "Hello #{params["name"]}"
}, name: "hello")

# create and run http server
HTTP::Server.new(->(context : Context) {
  result = router.match(context.request)
  if handler = result.handler
    handler.call(context, result.params)
  elsif result.allowed_methods.empty?
    context.response.respond_with_status(:not_found)
  else
    # respond_with_status would clear the Allow header
    context.response.status = :method_not_allowed
    context.response.headers["Allow"] = result.allowed_methods.join(", ")
  end
}).listen("0.0.0.0", 8080)
```

### Routes

| Segment       | Matches                                    |
| ------------- | ------------------------------------------ |
| `/users`      | the literal segment                        |
| `/:id`        | one non-empty segment, captured as `id`    |
| `/:id:d`      | same, if validator `d` accepts the value   |
| `/*path`      | the non-empty rest of the path, as `path`  |
| `/*path:name` | same, if validator `name` accepts the value |

- Matching priority is static > dynamic > catchall, segment by segment from the left. When a branch fails, the router
  backtracks to the next one. Dynamic segments at the same position are tried in the order they were mapped.
- A catchall must be the last segment. Param names must be unique within a route.
- Mapping a path again adds methods to it. Mapping a method that is already mapped for the path raises.
- Segments are percent-decoded after the path is split, so `%2F` never acts as a separator.
  Route definitions are decoded the same way: `/caf%C3%A9` and `/café` are the same route, and `/%3Aid` is the literal `:id`.
- Matching is strict: `/a` and `/a/` are different routes, and so are `/a/b` and `/a//b`.
  A request path must start with exactly one `/`, so `//a` and `a` never match `/a`.
  This keeps the router from seeing a different path than a proxy or cache in front of it.
- Routes must not contain `?` or `#`, and `match` expects a path without query string.
- `HEAD` falls back to the `GET` handler unless a `HEAD` handler is defined.
- If the path matches but the method does not, `result.allowed_methods` lists the allowed methods, for the `Allow` header of a 405 response.
- Define all routes before serving requests. Matching never mutates the router, so it is safe across threads.

### Security

Params are decoded but not sanitized. Validate them before use, especially catchalls:

- Neither the router nor `HTTP::Server` removes dot segments. `/files/../../etc/passwd` and `/files/%2e%2e/%2e%2e/etc/passwd`
  both yield `path = "../../etc/passwd"`. Never join a param into a filesystem path unchecked.
- Values may contain `/` (from `%2F`), NUL bytes (`%00`) and invalid UTF-8 (`%FF`).
  Use a validator, or `String#valid_encoding?`, where that matters.

### Validators

Built in: `w` (word characters), `a` (alphanumeric), `l` (letters), `d` (digits). Add your own:

```crystal
router.add_validator("hex", &.matches?(/\A[0-9a-f]+\z/))
router.map("GET", "/blobs/:sha:hex", handler)
```

### Building paths

```crystal
router.map(["GET", "PUT"], "/users/:id:d", handler, name: "user")
router.build("user", {id: 42}) # => "/users/42"
```

`build` percent-encodes values and checks them against the route's validators, so a built path always matches its route.
Invalid route definitions and failed builds raise `Radbas::Routing::Error`.

### Performance

No cache: every request walks the route tree, without copying the path. Static routes and misses allocate nothing.
`crystal run --release bench/router_bench.cr` on Apple Silicon:

| case               | time   | allocated |
| ------------------ | ------ | --------- |
| static             | 7.7ns  | 0B        |
| dynamic            | 102ns  | 192B      |
| catchall           | 79ns   | 208B      |
| not found          | 26ns   | 0B        |
| method not allowed | 100ns  | 144B      |

## Development

```sh
shards install
crystal build -o bin/ameba lib/ameba/bin/ameba.cr
crystal spec && crystal tool format --check && bin/ameba
crystal run --release bench/router_bench.cr
```

## Contributing

1. Fork it (<https://github.com/radbas/routing.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Johannes Rabausch](https://github.com/jrabausch) - creator and maintainer
