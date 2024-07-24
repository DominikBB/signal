import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleames/event
import gleames/handlers

pub type Store(event) =
  Subject(StoreOperations(event))

type InnerStore(event) {
  InnerStore(
    write_ahead_log: List(event),
    persistance_handler: handlers.PersistanceHandler(event),
  )
}

pub type StoreOperations(event) {
  Push(event: List(event.Event(event)))
  Get(reply_with: Subject(Result(List(event), String)), aggregate_id: String)
  // Used by the persistance layer to confirm the event is stored
  PersistanceState(id: String, completed: Bool)
  Shutdown
}
