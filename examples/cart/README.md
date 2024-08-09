# Example web application using emit and wisp

The example contains a HTMX powered frontend, so you can run it with `gleam server` and play around on `localhost`.

> ⚠️ The example uses the default in-memory persistance layer, so it will lose all data on server restart.

1. In the `domain.gleam` we define the models, and handlers for our business logic
2. In the `cart.gleam` we configure gleam, set up a route handler and configure wisp
3. In the `router.gleam` we handle api routes and use emit to get state and process commands

The domain in the example models a very rough shopping cart where you can add and remove items. As well as a revenue metric that counts the total amount of money made in completed orders.

To try it out, go to localhost:8000/cart/{enter any string here}, this will let you add items to a cart and complete a purchase. You can enter a different cart id into the url to get to a different cart and try it again. Throughout the process you will notice that revenue is counted across carts.
