import gleam/erlang/process.{type Subject}
import gleames/event.{type Event}

/// A function that applies an enum of commands and might produce events
/// 
pub type CommandHandler(state, command, event) =
  fn(command, state) -> Result(List(event), String)

/// A function that applies an enum of events to an aggregate, producing a representation of current state
/// 
pub type EventHandler(state, event) =
  fn(state, Event(event)) -> state

/// A function that handles persistance of events
/// 
pub type PersistanceHandler(event) {
  PersistanceHandler(
    get: fn(String) -> Result(List(event), String),
    push_events: fn(List(event)) -> Result(List(event), String),
  )
}

/// Consumers are called when an event is produced
/// 
pub type Consumer(event) {
  Consumer(Subject(Event(event)))
}
