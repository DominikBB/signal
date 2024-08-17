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

-   [ ] TODO
