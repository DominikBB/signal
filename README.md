[![Package Version](https://img.shields.io/hexpm/v/signal)](https://hex.pm/packages/signal)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/signal/)

<h1 align="center">Signal</h1>

<div align="center">
    Makes event sourcing a piece of cake! 🍰
</div>

---

Event sourcing is a software design pattern where the state of an application is determined by a sequence of events. It differs from traditional software modeling by storing and replaying events to derive the current state, rather than directly modifying the state through mutable operations.

In event sourcing, we process **commands**, which, informed by a **model**, output **events**. The events are then applied to the model to produce new state. The events are persisted instead of the model itself, allowing for an auditable, append only storage model that supports history, rollbacks, and generally avoids need for db migrations.

> **Command** -> produces -> **Events** -> mutates -> **Model**

The model is often referred to as an Aggregate, inspired by the Domain Driven Design approach.

It can make your applications very easy to reason about and extend.

```sh
gleam add signal
```

## Features

-   A **declarative API** that does not intrude into your domain model
-   **Effortless extensibility** allowing for custom projections, metrics and any other kind of compute to be triggered on event generation
-   High degree of **scalability** harnessing the power of OTP

## Example

### Creating an aggregate

Aggregates are identified by a unique string id, and can then be retrieved using that id.

```gleam
use cart <- result.try(signal.create(signal, "new_unique_cart_id"))
```

### Processing a command

This will run your command on a given aggregate, which may produce an event resulting in a new state.

```gleam
case signal.handle_command(cart, domain.CompletePurchase) {
    Ok(new_state) -> todo
    Error(msg) -> todo
}
```

### Get aggregate state

This will get the state for a given aggregate. Signal manages a pool of in-memory aggregates to improve performance, if an aggregate is not in the pool, it will get events from the storage layer and derive the state.

```gleam
use aggregate <- result.try(signal.aggregate(signal, "id_of_aggregate"))
let state = signal.get_state(aggregate)
```

## Learning Signal

[Cart example](https://github.com/dominikbb/signal/tree/master/examples/cart) creates a web app using Signal, Wisp and HTMX.

## Road to v1

These are the features I see version 1 having:

-   [x] Logging handler for customizing logging
-   [x] Persistance layer test suite
-   [ ] Postgres persistance layer
-   [ ] Aggregate replay to a specific version
-   [ ] Genesis command handler for customizing creation of a new aggregate
-   [ ] Closure event handler, to make deleting and evicting aggregates more customizable
-   [ ] Aggregate pool management based on activity instead of a queue
-   [ ] Test and develop policy subscribers further
