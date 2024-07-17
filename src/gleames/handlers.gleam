/// A function that applies an enum of commands and might produce events
/// 
pub type CommandHandler(state, command, event) =
  fn(state, command) -> Result(List(event), String)

/// A function that applies an enum of events to an aggregate, producing a representation of current state
/// 
pub type EventHandler(state, event) =
  fn(state, event) -> state

/// A function that handles persistance of events
/// 
pub type PersistanceHandler(state, event) {
  PersistanceHandler(
    get_aggregate: fn(String) -> Result(List(event), String),
    push_events: fn(List(event)) -> Result(List(event), String),
    push_snapshot: fn(state, String) -> Result(state, String),
  )
}
