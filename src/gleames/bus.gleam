import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleames/event.{type Event}
import gleames/store.{type Store}

pub type Bus(event) =
  Subject(BusMessage(event))

pub type InnerBus(event) {
  InnerBus(consumers: List(Subject(Event(event))), store: Store(event))
}

pub type BusMessage(event) {
  Push(Event(event))
  Shutdown
}

pub fn handle_bus_message(message: BusMessage(event), bus: InnerBus(event)) {
  case message {
    Push(event) -> todo
    Shutdown -> actor.Stop(process.Normal)
  }
}
