import gleam/erlang/process.{type Selector, type Subject}
import gleam/otp/actor
import gleam/string
import gleames/bus.{type Bus}
import gleames/configuration
import gleames/event.{type Event}
import gleames/handlers

pub type Aggregate(aggregate, command, event) =
  Subject(AggregateMessage(aggregate, command, event))

pub opaque type InnerAggregate(aggregate, command, event) {
  InnerAggregate(
    id: String,
    version: Int,
    state: aggregate,
    command_handler: handlers.CommandHandler(aggregate, command, event),
    event_handler: handlers.EventHandler(aggregate, event),
    bus: Bus(event),
  )
}

pub type AggregateMessage(aggregate, command, event) {
  State(reply_with: Subject(aggregate))
  Identity(reply_with: Subject(String))
  HandleCommand(
    reply_with: Subject(Result(List(Event(event)), String)),
    command,
  )
  Shutdown
}

pub fn aggregate_init(
  id: String,
  events: List(event.Event(event)),
  config: configuration.AggregateConfiguration(aggregate, command, event),
  bus: Bus(event),
) {
  fn() {
    let aggregate =
      InnerAggregate(
        id: id,
        version: 0,
        state: config.initial_state,
        command_handler: config.command_handler,
        event_handler: config.event_handler,
        bus: bus,
      )

    actor.Ready(
      state: initial_hydration(aggregate, events, config.event_handler),
      selector: process.new_selector(),
    )
  }
}

pub fn initial_hydration(
  agg: InnerAggregate(aggregate, command, event),
  events: List(Event(event)),
  handle: handlers.EventHandler(aggregate, event),
) {
  case events {
    [] -> agg
    [next] -> InnerAggregate(..agg, version: agg.version + 1, state: agg.state)
    [next, ..rest] ->
      InnerAggregate(..agg, version: agg.version + 1, state: agg.state)
      |> initial_hydration(rest, handle)
  }
}

pub fn handle_aggregate_operations(
  operation: AggregateMessage(aggregate, command, event),
  agg: InnerAggregate(aggregate, command, event),
) {
  case operation {
    State(client) -> {
      process.send(client, agg.state)
      actor.continue(agg)
    }
    Identity(client) -> {
      process.send(client, agg.id)
      actor.continue(agg)
    }
    HandleCommand(client, command) ->
      case agg.command_handler(command, agg.state) {
        Ok(new_aggregate_events) -> {
          let new_state =
            aggregate_update_workflow(
              StateUpdate(agg, []),
              new_aggregate_events,
            )
          process.send(client, Ok(new_state.events))
          actor.continue(InnerAggregate(..agg, state: new_state.agg.state))
        }
        Error(msg) -> {
          process.send(client, Error(msg))
          actor.continue(agg)
        }
      }
    Shutdown -> actor.Stop(process.Normal)
  }
}

type StateUpdate(aggregate, command, event) {
  StateUpdate(
    agg: InnerAggregate(aggregate, command, event),
    events: List(Event(event)),
  )
}

fn aggregate_update_workflow(
  state_pair: StateUpdate(aggregate, command, event),
  queue: List(event),
) {
  case queue {
    [] -> state_pair
    [next] -> update_aggregate(state_pair, next)
    [next, ..rest] ->
      update_aggregate(state_pair, next) |> aggregate_update_workflow(rest)
  }
}

fn update_aggregate(
  current: StateUpdate(aggregate, command, event),
  event: event,
) {
  current
  |> hydrate_event(event)
  |> send_event_to_bus(current)
  |> hydrate_aggregate_with_update(current)
}

fn hydrate_event(current: StateUpdate(aggregate, command, event), event: event) {
  event.Event(
    aggregate_version: current.agg.version + 1,
    aggregate_id: current.agg.id,
    event_name: string.inspect(event),
    data: event,
  )
}

fn hydrate_aggregate_with_update(
  event: Event(event),
  current: StateUpdate(aggregate, command, event),
) {
  StateUpdate(
    agg: InnerAggregate(
      ..current.agg,
      version: event.aggregate_version,
      state: current.agg.event_handler(current.agg.state, event),
    ),
    events: [event, ..current.events],
  )
}

fn send_event_to_bus(
  event: Event(event),
  current: StateUpdate(aggregate, command, event),
) {
  process.send(current.agg.bus, bus.Push(event))
  event
}
