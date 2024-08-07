[![Package Version](https://img.shields.io/hexpm/v/gleames)](https://hex.pm/packages/gleames)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gleames/)

<h1 align="center">Emit</h1>

<div align="center">
    Makes event sourcing a piece of cake! 🍰
</div>

---

## Features

-   A **declarative API** that does not intrude into your domain model
-   **Effortless extensibility** allowing for custom projections, metrics and any other kind of compute to be triggered on event generation
-   High degree of **scalability** harnessing the power of OTP

## Example

```gleam

import emit

pub type BlogPost = {
  BlogPost(title: String, body: String)
}

pub type PostCommand {
  SetPostTitle(String)
  SetPostBody(String)
}

pub type PostEvent {
  PostTitleChanged(String)
  PostBodyChanged(String)
}

pub fn main() {

  // Configure an aggregate
  let aggregate_config = AggregateConfig(
    initial_state: my_default_aggregate,
    command_handler: my_command_handler,
    event_handler: my_event_handler
  )

  // Configure emit
  let store = emit.configure(aggregate_config)
  |> with_persistance_layer(my_storage)
  |> with_subscriber(my_notification_client)
  |> with_subscriber(my_metrics_counter)
  |> start()

  // Process a command
  let result = emit.get_aggregate(em, "how-to-gleam")
  |> emit.handle_command(SetPostTitle("how to gleam"))
  // BlogPost("how to gleam", "")
}
```
