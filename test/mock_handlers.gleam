import gleam/list.{append}
import gleames/handlers
import gleam/otp/actor
import gleam/erlang/process.{type Subject}

pub fn mock_persistance(
  with: List(event),
) -> handlers.PersistanceHandler(state, event) {
  let assert Ok(actor) = actor.start(with, mock_persistance_actor)
  let get_aggregate = fn(id: String) { process.call(actor, GetAggregate, 10) }
  let push_events = fn(event: List(event)) { Ok(append(with, event)) }
  let push_snapshot = fn(state: state, _subject: String) { Ok(state) }
  handlers.PersistanceHandler(get_aggregate, push_events, push_snapshot)
}

type Messages(event) {
  Shutdown
  PushEvent(event)
  PushSnapshot(event)
  GetAggregate(String, Subject(Result(List(event), String)))
  GetProjection(String, Subject(Result(List(event), String)))
}

fn mock_persistance_actor(
  message: Messages(e),
  events: List(e),
) -> actor.Next(Messages(e), List(e)) {
  case message {
    PushEvent(event) -> {
      actor.continue([event, ..events])
    }

    PushSnapshot(event) -> {
      actor.continue([event, ..events])
    }

    GetAggregate(id, subject) -> {
      actor.continue([event, ..events])
    }

    GetProjection(id, subject) -> {
      actor.continue([event, ..events])
    }
    Shutdown -> {
      actor.Stop(process.Normal)
    }
  }
}
