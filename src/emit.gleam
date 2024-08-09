import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/task
import gleam/result
import gleam/set
import gleam/string

// -----------------------------------------------------------------------------
//                              Exorted interface                               
// -----------------------------------------------------------------------------

// ----------------------------- Exported Types --------------------------------

/// A base emit process which supervises the behind the scenes stuff and exposes some functionality.
/// 
///
pub type Emit(aggregate, command, event) =
  process.Subject(EmitMessages(aggregate, command, event))

/// The base emit process, it handles the internal operation of emit for a given aggregate type.
/// 
///
pub opaque type EmitMessages(aggregate, command, event) {
  GetPool(reply_with: process.Subject(Pool(aggregate, command, event)))
  Shutdown
}

/// Represents a base event type that is used throughout emit, in event handlers you are able to use this information if needs be.
/// 
///
pub type Event(event) {
  Event(
    aggregate_version: Int,
    aggregate_id: String,
    event_name: String,
    data: event,
  )
}

/// An aggregate is an actor managed by emit that holds the state, processes commands and events.
/// 
/// You can send messasges to this aggregate and interact with it, but emit provides a number of pre-built functions to help with that.
/// 
pub type Aggregate(aggregate, command, event) =
  process.Subject(AggregateMessage(aggregate, command, event))

/// This is where you put your domain / business logic, a function that has access to the current state of your aggregate, and can decided what to do with a given command.
/// 
/// The command handler may return an Error(String), or a list of events. Most of the time, you will be producing one event but in some cases you will find a need for producing multiple.
/// 
/// Commands are only triggered once, so they can contain side-effects.
/// 
/// Basic example:
/// ```gleam
/// pub fn handle_post_commands(command: PostCommands, post: Post) {
///   case command {
///     UpdatePostContent(title, text) -> Ok([PostUpdated(title, text)])
///     PublishPost -> {
///       case state {
///         s if s.title == "" -> Error("Cannot publish a post without a title!")
///         _ -> Ok([PostPublished()])
///       }
///     }
///   }
/// } 
/// ```
/// 
/// > ⚠️ It is best practice to wrap the handler in a higher order function, this lets you inject dependencies and improves extensibility.
/// Best practice:
/// 
/// ```gleam
/// pub fn handle_post_commands(notify: NotificationService) -> emit.CommandHandler(Post, PostCommands, PostEvents) {
///   fn (command: PostCommands, post: Post) {
///     case command {
///       UpdatePostContent(title, text) -> Ok([PostUpdated(title, text)])
///       PublishPost -> {
///         case state {
///           s if s.title == "" -> Error("Cannot publish a post without a title!")
///           _ -> { 
///             notification.send(notify, "Just published a new post - " <> post.title)
///             Ok([PostPublished()]) }
///         }
///       }
///     }
///   }
/// } 
/// ```
/// 
pub type CommandHandler(state, command, event) =
  fn(command, state) -> Result(List(event), String)

/// A function that describes how events translate into state of your aggregate. Events handlers are used to update the aggregate after processing commands, and to hydrate the aggregate from storage.
/// 
/// Most of the time these are simple data mapping functions.
/// 
/// Basic example:
/// ```gleam
/// pub fn handle_post_events(post: Post, event: PostEvents) {
///   case command {
///     PostUpdated(title, text) -> Post(..post, title: title, text: text)
///     PostPublished -> Post(..post, published: True) 
///   }
/// } 
/// ```
/// 
pub type EventHandler(state, event) =
  fn(state, Event(event)) -> state

/// When implementing a custom persistance layer, emit expects an actor that handles these messages
/// 
/// - GetStoredEvents: used for hydrating aggregates from storage
/// - IsIdentityAvailable: used to ensure duplicate ids cannot be created
/// - StoreEvents: used to persist a list of new events
/// - ShutdownPersistanceLayer: helper to let you shut down your actor, emit will not trigger this message
/// 
/// > ⚠️ Persistance actor has to report the result of the StoreEvents message in form of a PersistanceState event. This allows emit to handle a write ahead log and batch event storage operations. 
/// 
pub type PersistanceInterface(event) {
  GetStoredEvents(process.Subject(Result(List(Event(event)), String)), String)
  IsIdentityAvailable(process.Subject(Result(Bool, String)), String)
  StoreEvents(List(Event(event)))
  ShutdownPersistanceLayer
}

/// Subscribers are triggered on **all** events produced by all aggregates, and serve as a great way to extend your system.
/// 
/// Subscribers cannot modify or produce events.
/// 
/// These are generally great for creating different read models of your data, reporting, and reacting to certain events. 
/// 
///  
/// - Consumer: is an actor that consumes events, and can do whatever it wants with them, and give the user full control of the state, lifecycle and everything elese.
/// - Policy: is a one-of task that should run on an event, at the moment there is no retries and emit will ignore the return values of these tasks.
/// 
/// > 🛑 Policies are early in development, not well tested and might result in performance bottlenecks.
/// 
pub type Subscriber(state, event) {
  Consumer(process.Subject(ConsumerMessage(state, event)))
  Policy(task.Task(Event(event)))
}

/// Consumers are actors that should receive and handle these messages.
/// 
/// - Consume: is the only message triggered by emit, and it is triggered on all events processed by the service
/// 
/// Other messages are there for user convenience.
/// 
pub type ConsumerMessage(state, event) {
  Consume(Event(event))
  GetConsumerState(reply: process.Subject(state))
  ShutdownConsumer
}

/// Configures the internals of an emit service.
///
pub opaque type EmitConfig(aggregate, state, command, event) {
  EmitConfig(
    aggregate: AggregateConfig(aggregate, command, event),
    persistance_handler: Option(process.Subject(PersistanceInterface(event))),
    subscribers: List(Subscriber(state, event)),
    pool_size: Int,
  )
}

/// Configures the aggregate processed by the emit service.
///
pub type AggregateConfig(aggregate, command, event) {
  AggregateConfig(
    initial_state: aggregate,
    command_handler: CommandHandler(aggregate, command, event),
    event_handler: EventHandler(aggregate, event),
  )
}

// --------------------------- Exported functions ------------------------------

/// This is a configuration object that lets you set up your emit instance.
/// 
/// You should put the configuration somewhere in your app's startup code.
/// 
/// ```gleam
/// let aggregate_config = AggregateConfig(
///   initial_state: my_default_aggregate,
///   command_handler: my_command_handler,
///   event_handler: my_event_handler
/// )
/// 
/// let store = emit.configure(aggregate_config)
/// |> with_persistance_layer(my_storage)
/// |> with_subscriber(my_notification_client)
/// |> with_subscriber(my_metrics_counter)
/// |> start()
/// ```
pub fn configure(
  agg: AggregateConfig(aggregate, command, event),
) -> EmitConfig(aggregate, state, command, event) {
  EmitConfig(
    aggregate: agg,
    persistance_handler: None,
    subscribers: [],
    pool_size: 100,
  )
}

/// Subscribers can be one-of tasks (policies) or actors (consumers) that consume events generated by the aggregate.
/// They are called for each event produced by all aggregates.
///  
/// This is a great way of projecting state in a very specific way. Think of it as letting you create different read models of your data, or trigger some other specifics when an event is generated.
///
/// You can event use this method to trigger commands to your other aggregates, but be careful, that can make it difficult to track the state of you application!
///
/// *Example policy:*
/// ```gleam
/// fn email_readers(event: MyBlogEvent) {
///   case event {
///     PostPublished -> {
///       email_everyone_interested(...)
///       Ok(Nil)
///     }
///     _ -> Ok(Nil)
///   }
/// }
/// ```
/// Couple of notes on policies:
/// - Emit will ignore return values of these functions
/// - WIP Emit currently does not retry failed policies, it will do in the future
///  
/// *Example consumer:*
/// ```gleam
/// fn event_counter( message: MyBlogEvent, event_count: Int ) {
///   case messasge {
///     Shutdown -> actor.stop(process.Normal)
///     _ -> actor.continue(event_count + 1)
///   }
/// } 
/// ```
/// There are a few things to not about Consumers:
/// - Emit will not start or stop your consumers, their lifetime is in your control.
/// - Emit will ignore any returned data
/// - Your actor should accept the messages which are actually the Events you defined at configuration time
/// 
pub fn with_subscriber(
  config: EmitConfig(aggregate, state, command, event),
  sub: Subscriber(state, event),
) -> EmitConfig(aggregate, state, command, event) {
  EmitConfig(..config, subscribers: [sub, ..config.subscribers])
}

/// Configures emit to store events using a particular persistance layer.
/// 
/// Emit will default to an **in-memory store** which is recommended for development.
/// 
/// WIP - I am working on some persistance layers, but for now, you can bring your own, or play around with in-memory persistance.
/// 
pub fn with_persistance_layer(
  config: EmitConfig(aggregate, state, command, event),
  persist: process.Subject(PersistanceInterface(event)),
) -> EmitConfig(aggregate, state, command, event) {
  EmitConfig(..config, persistance_handler: Some(persist))
}

/// Defines the maximum number of aggregates kept in memory. **Defaults to 100**,
/// lower it if you desire lower memory consumption, increase it if you desire higher performance.
/// 
/// When an aggregate which is not in the pool is requested, emit has to rebuild it from events in the database.
/// 
/// > ⚠️ **Large aggregates** that contain a lot of data are an **anti-pattern** in event sourcing, instead of lowering the pool size,
/// > you might want to consider breaking up your aggregate and redesigning it, or storing some data using a different persistance method.
/// 
pub fn with_pool_size_limit(
  config: EmitConfig(aggregate, state, command, event),
  aggregates_in_memory: Int,
) {
  EmitConfig(..config, pool_size: aggregates_in_memory)
}

/// Starts the emit services and returns a subject used to interact with the event store.
/// 
pub fn start(config: EmitConfig(aggregate, state, command, event)) {
  use service <- result.try(emit_init(config))

  actor.start(Nil, emit_handler(service))
}

/// Use this function to retrieve a particular aggregate from the emit event store. This will return a subject which can then be used to interact with state of you aggregate, or process further commands.
/// 
/// *Command handling example:*
/// ```gleam
/// let result = emit.get_aggregate(em, "how-to-gleam")
/// |> emit.handle_command(CommentOnPost("how-to-gleam"))
/// ```
///
/// *Getting state example:*
/// ```gleam
/// let post = emit.get_aggregate(em, "how-to-gleam")
/// |> emit.get_state()
/// ```
pub fn aggregate(
  emit: Emit(aggregate, command, event),
  id: String,
) -> Result(Aggregate(aggregate, command, event), String) {
  let pool = process.call(emit, GetPool, 5)
  process.call(pool, GetAggregate(_, id), 5)
}

/// Creates a new aggregate with a given ID.
/// 
/// The ID needs to be unique, otherwise creation will fail.
/// 
pub fn create(
  emit: Emit(aggregate, command, event),
  id: String,
) -> Result(Aggregate(aggregate, command, event), String) {
  let pool = process.call(emit, GetPool, 5)
  process.call(pool, CreateAggregate(_, id), 5)
}

/// Use this function to have your aggregate process a command.
/// 
/// ```gleam
/// let result = emit.get_aggregate(em, "how-to-gleam")
/// |> emit.handle_command(CreatePost("how-to-gleam"))
/// ```
/// 
pub fn handle_command(
  agg: Aggregate(aggregate, command, event),
  command: command,
) -> Result(aggregate, String) {
  process.call(agg, HandleCommand(_, command), 5)
}

/// Use this function to get the current state of your aggregate.
/// 
/// ```gleam
/// let post = emit.get_aggregate(em, "how-to-gleam")
/// |> emit.get_state()
/// ```
pub fn get_state(agg: Aggregate(aggregate, command, event)) -> aggregate {
  process.call(agg, State(_), 5)
}

/// Gets the id of the aggregate actor.
/// 
pub fn get_id(agg: Aggregate(aggregate, command, event)) -> String {
  process.call(agg, Identity(_), 5)
}

/// Gets the current size of the aggregate pool in memory, mainly for testing.
/// 
pub fn get_current_pool_size(emit: Emit(aggregate, command, event)) -> Int {
  let pool = process.call(emit, GetPool(_), 5)

  process.call(pool, PoolSize(_), 5)
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

fn emit_init(config: EmitConfig(aggregate, state, command, event)) {
  use store_handler <- result.try(result.replace_error(
    set_up_store_handler(config.persistance_handler),
    actor.InitTimeout,
  ))
  use store <- result.try(actor.start(#([], []), store_handler))
  use bus <- result.try(actor.start(Nil, bus_handler(config.subscribers, store)))
  use pool <- result.try(actor.start(
    dict.new(),
    pool_handler(config.aggregate, bus, store, config.pool_size),
  ))

  Ok(EmitService(pool: pool, bus: bus, store: store))
}

fn emit_handler(cfg: EmitService(aggregate, command, event)) {
  fn(message: EmitMessages(aggregate, command, event), _state: Nil) {
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

type AggregateState(aggregate, command, event) {
  AggregateState(version: Int, state: aggregate)
}

pub type AggregateMessage(aggregate, command, event) {
  State(reply_with: process.Subject(aggregate))
  Identity(reply_with: process.Subject(String))
  HandleCommand(reply_with: process.Subject(Result(aggregate, String)), command)
  ShutdownAggregate
}

fn aggregate_init(
  events: List(Event(event)),
  cfg: AggregateConfig(aggregate, command, event),
) {
  fn() {
    let aggregate = AggregateState(version: 0, state: cfg.initial_state)

    actor.Ready(
      state: events
        |> list.unique()
        |> list.sort(fn(e1, e2) {
          int.compare(e1.aggregate_version, e2.aggregate_version)
        })
        |> list.fold([], fn(dedup, event) {
          case
            list.any(dedup, fn(d: Event(event)) {
              d.aggregate_version == event.aggregate_version
            })
          {
            True -> dedup
            False -> list.append(dedup, [event])
          }
        })
        |> list.fold(aggregate, fn(agg, e) {
          apply_event(e, cfg.event_handler, agg)
        }),
      selector: process.new_selector(),
    )
  }
}

fn aggregate_handler(
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

type Pool(aggregate, command, event) =
  process.Subject(PoolMessage(aggregate, command, event))

type PoolMessage(aggregate, command, event) {
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
  PoolSize(reply_with: process.Subject(Int))
  ShutdownPool
}

fn pool_handler(
  config: AggregateConfig(aggregate, command, event),
  bus: Bus(event),
  store: Store(event),
  max_size: Int,
) {
  fn(
    operation: PoolMessage(aggregate, command, event),
    state: Dict(String, #(Aggregate(aggregate, command, event), Int)),
  ) {
    case operation {
      CreateAggregate(client, with_id) -> {
        let exists_in_store = store_has_aggregate(store, with_id)
        let exists_in_pool = dict.has_key(state, with_id)

        case exists_in_store, exists_in_pool {
          False, False -> {
            case start_aggregate(config, bus, with_id, []) {
              Ok(agg) -> {
                process.send(client, Ok(agg))
                actor.continue(
                  dict.insert(
                    evict_aggregates_workflow(max_size, state),
                    with_id,
                    #(agg, dict.size(state) + 1),
                  ),
                )
              }
              error -> {
                process.send(client, error)
                actor.continue(state)
              }
            }
          }
          _, _ -> {
            process.send(
              client,
              Error("Aggregate ID must be unique, " <> with_id <> " is not!"),
            )
            actor.continue(state)
          }
        }
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
            dict.insert(state, id, #(aggregate, dict.size(state) + 1))
            process.send(client, Ok(aggregate))
          }
          Error(msg) -> process.send(client, Error(msg))
        }
        actor.continue(state)
      }
      PoolSize(s) -> {
        process.send(s, dict.to_list(state) |> list.length())
        actor.continue(state)
      }
      ShutdownPool -> actor.Stop(process.Normal)
    }
  }
}

fn evict_aggregates_workflow(
  max_size: Int,
  state: Dict(String, #(Aggregate(aggregate, command, event), Int)),
) {
  // Happens before insertion of aggregate into pool, hence - 1
  case dict.size(state) >= max_size {
    True -> {
      let eviction_list =
        dict.to_list(state)
        |> list.filter(fn(agg) {
          let #(_, #(_, position)) = agg
          position >= max_size
        })
        |> list.map(fn(agg) {
          let #(id, #(agg, _)) = agg
          process.send(agg, ShutdownAggregate)
          id
        })

      dict.drop(state, eviction_list)
    }
    False -> state
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
  dict: Dict(String, #(Aggregate(aggregate, command, event), Int)),
  id: String,
) {
  case dict.get(dict, id) {
    Ok(#(value, _)) -> Ok(value)
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
      aggregate_init(events, config),
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

type Bus(event) =
  process.Subject(BusMessage(event))

type BusMessage(event) {
  PushEvent(Event(event))
  ShutdownBus
}

fn bus_handler(subscribers: List(Subscriber(state, event)), store: Store(event)) {
  fn(message: BusMessage(event), _state: Nil) {
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

fn notify_subscribers(
  event: Event(event),
  consumers: List(Subscriber(state, event)),
) {
  case consumers {
    [] -> Nil
    [Consumer(s)] -> process.send(s, Consume(event))
    [Policy(t)] -> {
      let _ = task.try_await(t, 5)
      Nil
    }
    [Consumer(s), ..rest] -> {
      process.send(s, Consume(event))
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

/// An internal actor used to manage storage of events.
/// 
pub type Store(event) =
  process.Subject(StoreMessages(event))

/// Messages handled by the Store actor, when creating custom persistance layers, you should report persistance state to PersistanceState.
/// 
pub type StoreMessages(event) {
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
  PersistanceState(ids: List(Event(event)), completed: Bool)
  ShutdownStore
}

fn set_up_store_handler(
  persistor: Option(process.Subject(PersistanceInterface(event))),
) {
  case persistor {
    Some(p) -> Ok(store_handler(p))
    None -> {
      case actor.start([], in_memory_persistance_handler) {
        Ok(s) -> Ok(store_handler(s))
        _ -> Error("Failed to spin up the in memory persistance layer!")
      }
    }
  }
}

/// Maintains a write ahead log to keep the system performant regardless of the persitance layer
/// 
fn store_handler(persistor: process.Subject(PersistanceInterface(event))) {
  fn(
    message: StoreMessages(event),
    state: #(List(Event(event)), List(Event(event))),
  ) {
    case message {
      StoreEvent(e) -> {
        let #(wal, processing) = state
        case list.is_empty(processing) {
          False -> actor.continue(#([e, ..wal], processing))
          True -> {
            process.send(persistor, StoreEvents([e, ..wal]))
            actor.continue(#([], list.append(wal, processing)))
          }
        }
      }
      GetEvents(s, id) -> {
        let events = process.call(persistor, GetStoredEvents(_, id), 5)
        process.send(s, events)
        actor.continue(state)
      }
      IdExists(s, id) -> {
        let result = process.call(persistor, IsIdentityAvailable(_, id), 5)
        process.send(s, result)
        actor.continue(state)
      }
      PersistanceState(processed, _) -> {
        let #(wal, events_being_processed) = state
        let #(_, not_yet_processed) =
          list.partition(events_being_processed, fn(e) {
            list.contains(processed, e)
          })

        actor.continue(#(wal, not_yet_processed))
      }
      ShutdownStore -> actor.Stop(process.Normal)
    }
  }
}

// -----------------------------------------------------------------------------
//                         In memory persistance layer                          
// -----------------------------------------------------------------------------

fn in_memory_persistance_handler(
  message: PersistanceInterface(event),
  state: List(Event(event)),
) {
  case message {
    GetStoredEvents(s, aggregate_id) -> {
      process.send(
        s,
        Ok(list.filter(state, fn(e) { e.aggregate_id == aggregate_id })),
      )
      actor.continue(state)
    }
    IsIdentityAvailable(s, aggregate_id) -> {
      case list.any(state, fn(e) { e.aggregate_id == aggregate_id }) {
        True -> process.send(s, Ok(True))
        False -> process.send(s, Ok(False))
      }

      actor.continue(state)
    }
    StoreEvents(events) -> actor.continue(list.append(state, events))
    ShutdownPersistanceLayer -> actor.Stop(process.Normal)
  }
}
