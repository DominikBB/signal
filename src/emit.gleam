import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/task
import gleam/result
import gleam/string

// -----------------------------------------------------------------------------
//                              Exorted interface                               
// -----------------------------------------------------------------------------

// ----------------------------- Exported Types --------------------------------

/// A base emit process which supervises the behind the scenes stuff and exposes some functionality 
///
pub type Emit(aggregate, command, event) =
  process.Subject(EmitMessages(aggregate, command, event))

/// The base emit process can get state of your aggregate based on the id.
/// 
/// It sets up a supervision tree like so:
/// ```mermaid
/// flowchart TD
/// em((Emit))
/// p((Process pool))
/// b((Event bus))
/// s((Event store))
/// subgraph actors
/// actor1
/// actor2
/// end
/// em --> p
/// em --> b
/// em --> s
/// p --> actors
/// ```
///
pub opaque type EmitMessages(aggregate, command, event) {
  GetPool(reply_with: process.Subject(Pool(aggregate, command, event)))
  Shutdown
}

/// Represents a base event type that is used throughout emit
///
pub type Event(event) {
  Event(
    aggregate_version: Int,
    aggregate_id: String,
    event_name: String,
    data: event,
  )
}

/// An aggregate is an actor managed by emit that holds the state, processes commands and events
/// 
/// You can send messasges to this aggregate and interact with it, but emit provides a number of pre-built functions to help with that.
/// 
pub type Aggregate(aggregate, command, event) =
  process.Subject(AggregateMessage(aggregate, command, event))

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
    get: fn(String) -> Result(List(Event(event)), String),
    push_events: fn(List(Event(event))) -> Result(List(Event(event)), String),
  )
}

/// Consumers are called when an event is produced
/// 
pub type Subscriber(event) {
  Consumer(process.Subject(Event(event)))
  Policy(task.Task(Event(event)))
}

/// Configures the internals of an emit service
///
pub opaque type EmitConfig(aggregate, command, event) {
  EmitConfig(
    aggregate: AggregateConfig(aggregate, command, event),
    persistance_handler: Option(PersistanceHandler(event)),
    subscribers: List(Subscriber(event)),
    pool_size: Int,
  )
}

/// Configures the internals of an emit service
///
pub type AggregateConfig(aggregate, command, event) {
  AggregateConfig(
    initial_state: aggregate,
    command_handler: CommandHandler(aggregate, command, event),
    event_handler: EventHandler(aggregate, event),
  )
}

// --------------------------- Exported functions ------------------------------

pub fn configure(
  agg: AggregateConfig(aggregate, command, event),
) -> EmitConfig(aggregate, command, event) {
  EmitConfig(
    aggregate: agg,
    persistance_handler: None,
    subscribers: [],
    pool_size: 100,
  )
}

pub fn with_subscriber(
  config: EmitConfig(aggregate, command, event),
  sub: Subscriber(event),
) -> EmitConfig(aggregate, command, event) {
  EmitConfig(..config, subscribers: [sub, ..config.subscribers])
}

pub fn with_persistance_layer(
  config: EmitConfig(aggregate, command, event),
  persist: PersistanceHandler(event),
) -> EmitConfig(aggregate, command, event) {
  EmitConfig(..config, persistance_handler: Some(persist))
}

pub fn start(
  config: EmitConfig(aggregate, command, event),
) -> Result(Emit(aggregate, command, event), actor.StartError) {
  use service <- result.try(emit_init(config))

  actor.start(Nil, emit_handler(service))
}

pub fn get_aggregate() -> Result(Aggregate(aggregate, command, event), String) {
  todo
}

pub fn create() -> Result(Aggregate(aggregate, command, event), String) {
  todo
}

pub fn handle_command() -> Result(aggregate, String) {
  todo
}

pub fn get_state() -> Result(aggregate, String) {
  todo
}

pub fn get_id() -> Result(String, String) {
  todo
}

// -----------------------------------------------------------------------------
//                                    Emit                                      
// -----------------------------------------------------------------------------

type EmitService(aggregate, command, event) {
  EmitService(
    pool: Pool(aggregate, command, event),
    bus: Bus(event),
    store: Store(event),
  )
}

fn emit_init(config: EmitConfig(aggregate, command, event)) {
  use store <- result.try(actor.start(
    [],
    store_handler(config.persistance_handler),
  ))

  use bus <- result.try(actor.start(Nil, bus_handler(config.subscribers, store)))

  use pool <- result.try(actor.start(
    dict.new(),
    pool_handler(config.aggregate, bus, store),
  ))

  Ok(EmitService(pool: pool, bus: bus, store: store))
}

fn emit_handler(cfg: EmitService(aggregate, command, event)) {
  fn(message: EmitMessages(aggregate, command, event), state: Nil) {
    case message {
      GetPool(s) -> {
        process.send(s, cfg.pool)
        actor.continue(Nil)
      }
      Shutdown -> actor.Stop(process.Normal)
    }
  }
}

// -----------------------------------------------------------------------------
//                                  Aggregate                                   
// -----------------------------------------------------------------------------

pub type AggregateState(aggregate, command, event) {
  AggregateState(version: Int, state: aggregate)
}

pub type AggregateMessage(aggregate, command, event) {
  State(reply_with: process.Subject(aggregate))
  Identity(reply_with: process.Subject(String))
  HandleCommand(reply_with: process.Subject(Result(aggregate, String)), command)
  ShutdownAggregate
}

pub fn aggregate_init(
  id: String,
  events: List(Event(event)),
  cfg: AggregateConfig(aggregate, command, event),
  bus: Bus(event),
) {
  fn() {
    let aggregate = AggregateState(version: 0, state: cfg.initial_state)

    actor.Ready(
      state: list.fold(events, aggregate, fn(agg, e) {
        apply_event(e, cfg.event_handler, aggregate)
      }),
      selector: process.new_selector(),
    )
  }
}

pub fn aggregate_handler(
  id: String,
  command_handler: CommandHandler(aggregate, command, event),
  event_handler: EventHandler(aggregate, event),
  bus: Bus(event),
) {
  fn(
    operation: AggregateMessage(aggregate, command, event),
    agg: AggregateState(aggregate, command, event),
  ) {
    case operation {
      State(client) -> {
        process.send(client, agg.state)
        actor.continue(agg)
      }
      Identity(client) -> {
        process.send(client, id)
        actor.continue(agg)
      }
      HandleCommand(client, command) ->
        case command_handler(command, agg.state) {
          Ok(events) -> {
            let new_state =
              list.fold(events, agg, fn(agg, e) {
                update_aggregate(
                  AggregateUpdateContext(id, bus, event_handler, agg),
                  e,
                )
              })
            process.send(client, Ok(new_state.state))
            actor.continue(new_state)
          }
          Error(msg) -> {
            process.send(client, Error(msg))
            actor.continue(agg)
          }
        }
      ShutdownAggregate -> actor.Stop(process.Normal)
    }
  }
}

type AggregateUpdateContext(aggregate, command, event) {
  AggregateUpdateContext(
    id: String,
    bus: Bus(event),
    event_handler: EventHandler(aggregate, event),
    aggregate: AggregateState(aggregate, command, event),
  )
}

fn update_aggregate(
  ctx: AggregateUpdateContext(aggregate, command, event),
  event: event,
) {
  event
  |> hydrate_event(ctx)
  |> send_event_to_bus(ctx)
  |> apply_event(ctx.event_handler, ctx.aggregate)
}

fn hydrate_event(
  event: event,
  ctx: AggregateUpdateContext(aggregate, command, event),
) {
  Event(
    aggregate_version: ctx.aggregate.version + 1,
    aggregate_id: ctx.id,
    event_name: string.inspect(event),
    data: event,
  )
}

fn apply_event(
  event: Event(event),
  handler: EventHandler(aggregate, event),
  agg: AggregateState(aggregate, command, event),
) -> AggregateState(aggregate, command, event) {
  // TODO Mby cross check the event and agg version to act on consistency issues
  AggregateState(version: agg.version + 1, state: handler(agg.state, event))
}

fn send_event_to_bus(
  event: Event(event),
  ctx: AggregateUpdateContext(aggregate, command, event),
) {
  process.send(ctx.bus, PushEvent(event))
  event
}

// -----------------------------------------------------------------------------
//                               Aggregate Pool                                 
// -----------------------------------------------------------------------------

pub type Pool(aggregate, command, event) =
  process.Subject(PoolMessage(aggregate, command, event))

pub type PoolMessage(aggregate, command, event) {
  CreateAggregate(
    reply_with: process.Subject(
      Result(Aggregate(aggregate, command, event), String),
    ),
    id: String,
  )
  GetAggregate(
    reply_with: process.Subject(
      Result(Aggregate(aggregate, command, event), String),
    ),
    id: String,
  )
  ShutdownPool
}

pub fn pool_handler(
  config: AggregateConfig(aggregate, command, event),
  bus: Bus(event),
  store: Store(event),
) {
  fn(
    operation: PoolMessage(aggregate, command, event),
    state: Dict(String, Aggregate(aggregate, command, event)),
  ) {
    case operation {
      CreateAggregate(client, with_id) -> {
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
      GetAggregate(client, id) -> {
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
      ShutdownPool -> actor.Stop(process.Normal)
    }
  }
}

fn store_has_aggregate(store: Store(event), key: String) {
  let response = process.call(store, IdExists(_, key), 5)

  case response {
    Error(_) -> True
    Ok(False) -> False
    Ok(True) -> True
  }
}

fn gather_aggregate(
  aggregate_initializer: fn(List(Event(event))) ->
    Result(Aggregate(aggregate, command, event), String),
  store: Store(event),
  dict: Dict(String, Aggregate(aggregate, command, event)),
  id: String,
) {
  case dict.get(dict, id) {
    Ok(value) -> Ok(value)
    Error(_) -> gather_aggregate_from_store(aggregate_initializer, store, id)
  }
}

fn gather_aggregate_from_store(
  aggregate_initializer: fn(List(Event(event))) ->
    Result(Aggregate(aggregate, command, event), String),
  store: Store(event),
  id: String,
) {
  case process.call(store, GetEvents(_, id), 5) {
    Error(msg) -> Error(msg)
    Ok(events) -> aggregate_initializer(events)
  }
}

fn start_aggregate(
  config: AggregateConfig(aggregate, command, event),
  bus: Bus(event),
  id: String,
  events: List(Event(event)),
) {
  case
    actor.start_spec(actor.Spec(
      aggregate_init(id, events, config, bus),
      5,
      aggregate_handler(id, config.command_handler, config.event_handler, bus),
    ))
  {
    Ok(actor) -> Ok(actor)
    _ -> Error("Could not initialize the actor: " <> id)
  }
}

// -----------------------------------------------------------------------------
//                                  Event Bus                                   
// -----------------------------------------------------------------------------

pub type Bus(event) =
  process.Subject(BusMessage(event))

pub type BusMessage(event) {
  PushEvent(Event(event))
  ShutdownBus
}

pub fn bus_handler(subscribers: List(Subscriber(event)), store: Store(event)) {
  fn(message: BusMessage(event), state: Nil) {
    case message {
      PushEvent(event) -> {
        notify_subscribers(event, subscribers)
        notify_store(event, store)
        actor.continue(Nil)
      }
      ShutdownBus -> actor.Stop(process.Normal)
    }
  }
}

fn notify_subscribers(event: Event(event), consumers: List(Subscriber(event))) {
  case consumers {
    [] -> Nil
    [Consumer(s)] -> process.send(s, event)
    [Policy(t)] -> {
      let _ = task.try_await(t, 5)
      Nil
    }
    [Consumer(s), ..rest] -> {
      process.send(s, event)
      notify_subscribers(event, rest)
    }
    [Policy(t), ..rest] -> {
      let _ = task.try_await(t, 5)
      notify_subscribers(event, rest)
    }
  }
}

fn notify_store(event: Event(event), store: Store(event)) {
  process.send(store, StoreEvent(event))
}

// -----------------------------------------------------------------------------
//                                 Event Store                                  
// -----------------------------------------------------------------------------

type Store(event) =
  process.Subject(StoreMessages(event))

pub opaque type StoreMessages(event) {
  StoreEvent(event: Event(event))
  GetEvents(
    reply_with: process.Subject(Result(List(Event(event)), String)),
    aggregate_id: String,
  )
  IdExists(
    reply_with: process.Subject(Result(Bool, String)),
    aggregate_id: String,
  )
  // Used by the persistance layer to confirm the event is stored
  PersistanceState(id: String, completed: Bool)
  ShutdownStore
}

fn store_handler(persistor: Option(PersistanceHandler(event))) {
  fn(message: StoreMessages(event), wal: List(Event(event))) {
    case message {
      StoreEvent(e) -> todo
      GetEvents(s, id) -> todo
      IdExists(s, id) -> todo
      PersistanceState(id, completed) -> todo
      ShutdownStore -> todo
    }
  }
}