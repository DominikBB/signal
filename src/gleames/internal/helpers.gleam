import gleam/option.{type Option, None, Some}

import gleames/handlers.{type EventHandler}

pub fn handle_events (event_handler: EventHandler(aggregate, event), events: List(event), state: aggregate) -> aggregate {
  case events {
    [] -> state
    [e, ..rest] -> event_handler(state, e) |> handle_events(event_handler, rest, _)}
}