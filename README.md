# Routing.cr

Simple HTTP router.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     radbas-routing:
       github: radbas/routing
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
  name = params["name"]?
  context.response.write "Hello #{name}".to_slice
})

# create and run http server
HTTP::Server.new(->(context : Context) {
  result = router.match(context.request)
  if result.match?
    result.handler.as(Handler).call(context, result.params)
  else
    context.response.status_code = 404
    context.response.write "Not Found".to_slice
  end
}).listen("0.0.0.0", 8080)
```

## Contributing

1. Fork it (<https://github.com/radbas/routing/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Johannes Rabausch](https://github.com/jrabausch) - creator and maintainer
