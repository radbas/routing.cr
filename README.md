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
router.map(["GET"], "/hello/:name", ->(context : Context, params : Params) {
  context.response.print "Hello #{params["name"]}"
}, :hello)

# create and run http server
HTTP::Server.new(->(context : Context) {
  result = router.match(context.request)
  if handler = result.handler
    handler.call(context, result.params)
  elsif result.methods.empty?
    context.response.respond_with_status(:not_found)
  else
    context.response.headers["Allow"] = result.methods.join(", ")
    context.response.respond_with_status(:method_not_allowed)
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

- Matching priority is static > dynamic > catchall. When a branch fails, the router backtracks to the next one.
- A catchall must be the last segment.
- Segments are percent-decoded after the path is split, so `%2F` never acts as a separator.
  The router does not normalize dot segments (`..`); that is the server's job.
- `HEAD` falls back to the `GET` handler unless a `HEAD` handler is defined.
- If the path matches but the method does not, `result.methods` lists the allowed methods, for the `Allow` header of a 405 response.
- Define all routes before serving requests. Matching never mutates the router, so it is safe across threads.

### Validators

Built in: `w` (word characters), `a` (alphanumeric), `l` (letters), `d` (digits). Add your own:

```crystal
router.add_validator("hex", &.matches?(/\A[0-9a-f]+\z/))
router.map(["GET"], "/blobs/:sha:hex", handler)
```

### Building paths

```crystal
router.map(["GET"], "/users/:id", handler, :user)
router.build(:user, {id: 42}) # => "/users/42"
```

Invalid route definitions and failed builds raise `Radbas::Routing::Error`.

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
