import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleames/event.{type Event}
import gleames/store.{type Store}

pub type Bus(event) =
  Subject(BusMessage(event))

pub type BusMessage(event) {
  Push(Event(event))
  Shutdown
}

pub fn handle_bus_message(
  consumers: List(Subject(Event(event))),
  store: Store(event),
) {
  fn(message: BusMessage(event), state: Nil) {
    case message {
      Push(event) -> {
        notify_consumers(event, consumers)
        notify_store(event, store)
        actor.continue(Nil)
      }
      Shutdown -> actor.Stop(process.Normal)
    }
  }
}

fn notify_consumers(
  event: event.Event(event),
  consumers: List(Subject(Event(event))),
) {
  case consumers {
    [] -> Nil
    [s] -> process.send(s, event)
    [s, ..rest] -> {
      process.send(s, event)
      notify_consumers(event, rest)
    }
  }
}

fn notify_store(event: event.Event(event), store: Store(event)) {
  process.send(store, store.Push([event]))
}
