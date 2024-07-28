import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleames/aggregate.{type Aggregate}
import gleames/bus
import gleames/configuration
import gleames/event
import gleames/store

pub type Pool(aggregate, command, event) =
  Subject(PoolMessage(aggregate, command, event))

pub type PoolMessage(aggregate, command, event) {
  Create(
    reply_with: Subject(Result(Aggregate(aggregate, command, event), String)),
    id: String,
  )
  Get(
    reply_with: Subject(Result(Aggregate(aggregate, command, event), String)),
    id: String,
  )
  Shutdown
}

pub fn pool_handler(
  config: configuration.AggregateConfiguration(aggregate, command, event),
  bus: bus.Bus(event),
  store: store.Store(event),
) {
  fn(
    operation: PoolMessage(aggregate, command, event),
    state: Dict(String, Aggregate(aggregate, command, event)),
  ) {
    case operation {
      Create(client, with_id) -> {
        let exists_in_store = store_has_aggregate(store, with_id)
        let exists_in_pool = dict.has_key(state, with_id)

        case exists_in_store, exists_in_pool {
          False, False -> {
            case start_aggregate(config, bus, with_id, []) {
              Ok(agg) -> {
                dict.insert(state, with_id, agg)
                process.send(client, Ok(agg))
              }
              error -> process.send(client, error)
            }
          }
          _, _ -> {
            process.send(
              client,
              Error("Aggregate ID must be unique, " <> with_id <> " is not!"),
            )
          }
        }
        actor.continue(state)
      }
      Get(client, id) -> {
        case
          gather_aggregate(
            start_aggregate(config, bus, id, _),
            store,
            state,
            id,
          )
        {
          Ok(aggregate) -> {
            dict.insert(state, id, aggregate)
            process.send(client, Ok(aggregate))
          }
          Error(msg) -> process.send(client, Error(msg))
        }
        actor.continue(state)
      }
      Shutdown -> actor.Stop(process.Normal)
    }
  }
}

fn store_has_aggregate(store: store.Store(event), key: String) {
  let response = process.call(store, store.Exists(_, key), 5)

  case response {
    Error(_) -> True
    Ok(False) -> False
    Ok(True) -> True
  }
}

fn gather_aggregate(
  aggregate_initializer: fn(List(event.Event(event))) ->
    Result(Aggregate(aggregate, command, event), String),
  store: store.Store(event),
  dict: Dict(String, Aggregate(aggregate, command, event)),
  id: String,
) {
  case dict.get(dict, id) {
    Ok(value) -> Ok(value)
    Error(_) -> gather_aggregate_from_store(aggregate_initializer, store, id)
  }
}

fn gather_aggregate_from_store(
  aggregate_initializer: fn(List(event.Event(event))) ->
    Result(Aggregate(aggregate, command, event), String),
  store: store.Store(event),
  id: String,
) {
  case process.call(store, store.Get(_, id), 5) {
    Error(msg) -> Error(msg)
    Ok(events) -> aggregate_initializer(events)
  }
}

fn start_aggregate(
  config: configuration.AggregateConfiguration(aggregate, command, event),
  bus: bus.Bus(event),
  id: String,
  events: List(event.Event(event)),
) {
  case
    actor.start_spec(actor.Spec(
      aggregate.aggregate_init(id, events, config, bus),
      5,
      aggregate.handle_aggregate_operations,
    ))
  {
    Ok(actor) -> Ok(actor)
    _ -> Error("Could not initialize the actor: " <> id)
  }
}
