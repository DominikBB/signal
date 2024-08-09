# Example web application using emit and wisp

The example contains a HTMX powered frontend, so you can run it with `gleam server` and play around on `localhost`.

> ⚠️ The example uses the default in-memory persistance layer, so it will lose all data on server restart.

1. In the `domain.gleam` we define the models, and handlers for our business logic
2. In the `cart.gleam` we configure gleam, set up a route handler and configure wisp
3. In the `router.gleam` we handle api routes and use emit to get state and process commands
