/// A function that applies an enum of commands and might produce events
/// 
pub type CommandHandler(state, command, event, aggregate_error) =
  fn(state, command) -> Result(List(event), GleamesError(aggregate_error))

/// A function that applies an enum of events to an aggregate, producing a representation of current state
/// 
pub type EventHandler(state, event) =
  fn(state, event) -> state

/// A function that handles persistance of events
/// 
pub type PersistanceHandler(state, event, aggregate_error) {
  PersistanceHandler(
    get_aggregate: fn(String) ->
      Result(List(event), GleamesError(aggregate_error)),
    push_events: fn(List(event)) ->
      Result(List(event), GleamesError(aggregate_error)),
    push_snapshot: fn(state, String) ->
      Result(state, GleamesError(aggregate_error)),
  )
}

pub type GleamesError(aggregate_error) {
  OnAggregate(aggregate_error)
  OnPersistance(String)
  OnPublish(String)
}
