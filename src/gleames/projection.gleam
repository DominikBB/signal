import gleam/result.{map}

import gleames/handlers.{type EventHandler, type PersistanceHandler}
import gleames/internal/helpers.{handle_events}

/// A projection is a special view of events that is used to optimize read operations.
/// 
pub type Projection(projection) = fn(String) -> Result(projection, String)

/// Produces a function that handles projection fetching from the persistance layer.
/// 
pub fn create_projection(
  event_handler: EventHandler(projection, event),
  persistance: PersistanceHandler(projection, event),
  default_projection: projection,
  ) -> Projection(projection) {
  
  fn (id: String) -> Result(projection, String) {
    id
    |> persistance.get_aggregate()
    |> map(handle_events(event_handler, _, default_projection))
  }
}