import gleam/option.{type Option, None, Some}
import gleam/result.{map, try}
import gleames/handlers.{
  type CommandHandler, type EventHandler, type PersistanceHandler,
}
import gleames/internal/helpers.{handle_events}

/// Definition of the event store functions
/// 
pub type Aggregate(aggregate, event, command, aggregate_error) {
  Aggregate(
    handle: fn(String, command) ->
      Result(aggregate, GleamesError(aggregate_error)),
    create: fn(command) -> Result(aggregate, GleamesError(aggregate_error)),
    get: fn(String) -> Result(aggregate, GleamesError(aggregate_error)),
  )
}

pub fn create_aggregate(
  command_handler: CommandHandler(aggregate, command, event),
  event_handler: EventHandler(aggregate, event),
  persistance: PersistanceHandler(aggregate, event),
  default_aggregate: aggregate,
) -> Aggregate(aggregate, event, command, aggregate_error) {
  Aggregate(
    handle: fn(id: String, command: command) -> Result(
      aggregate,
      GleamesError(aggregate_error),
    ) {
      id
      |> persistance.get_aggregate()
      |> map(handle_events(event_handler, _, default_aggregate))
      |> try(command_handler(_, command))
      |> try(persistance.push_events(_))
      |> map(handle_events(event_handler, _, default_aggregate))
    },
    create: fn(command: command) -> Result(
      aggregate,
      GleamesError(aggregate_error),
    ) {
      command_handler(_, command)
      |> try(persistance.push_events(_))
      |> map(handle_events(event_handler, _, default_aggregate))
    },
    get: fn(id: String) -> Result(aggregate, String) {
      id
      |> persistance.get_aggregate()
      |> map(handle_events(event_handler, _, default_aggregate))
    },
  )
}
