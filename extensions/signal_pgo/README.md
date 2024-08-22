# signal_pgo

[![Package Version](https://img.shields.io/hexpm/v/signal_pgo)](https://hex.pm/packages/signal_pgo)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/signal_pgo/)

```sh
gleam add signal signal_pgo
```

This is a persistance layer for the signal event sourcing library, on application startup, it will run migrations to set up an events table, and then it will be able to store and load events from signal. To configure it, you need to provide a gleam_pgo config, as well as an encoder and decoder for your events.

The encoding and decoding is done to a String, because event data is stored as a TEXT field in postgres. This also allows for maximum flexibility, allowing you to control exactly how data is stored.

This flexibility lets you implement things like encryption, or avoid the performance overhead of JSON parsing.

## Usage

Set up a local database:

```sh
docker run --name your-db-name -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -p 5500:5432 -d postgres
```

Initiate the Signal_PGO and Signal, configure them:

```gleam
pub fn main() {

    // Create your typical Gleam PGO database config in your config code
    let pgo_config =
        pgo.Config(
            ..pgo.default_config(),
            host: "localhost",
            port: 5500,
            database: "signal_dev",
            user: "postgres",
            password: option.Some("postgres"),
            pool_size: 2,
        )

    // Start the Signal_PGO services, this will return two actors
    // First actor is the one you use to configure Signal
    // Second actor is a helper that saves and retrieves String blobs,
    //      useful for persisting your event consumer state, as sort of a projection.
    //
    let assert Ok(#(aggregate_persistance, _projection_persistance)) =
        |> signal_pgo.start(pgo_config, your_event_encoder, your_event_decoder)

    let aggregate_configuration =
        signal.AggregateConfig(
        initial_state: your_aggregate_initial_state,
        command_handler: your_command_handler,
        event_handler: your_event_handler,
        )

    // Use the with_persistance to configure Signal with this persistance layer
    let assert Ok(es_service) =
        signal.configure(aggregate_configuration)
        |> signal.with_persistence(aggregate_persistance)
        |> signal.with_subscriber(signal.Consumer(revenue_report))
        |> signal.start()

}
```

Your application will now store events produced by the aggregate in the database, and use it to hydrate aggregates when needed.

## Projection store

Signal PGO will create a projection store table which can store any blobs of TEXT data. This is a rudimentary helper to help you store your projection state. The end goal is to offer proper projections functionality in Signal in the future, but for the time being you have to handle most of the logic yourself.
