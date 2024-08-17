import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/task
import gleam/result
import gleam/string

const process_call_timeout = 100

// -----------------------------------------------------------------------------
//                              Exorted interface                               
// -----------------------------------------------------------------------------

// ----------------------------- Exported Types --------------------------------

/// Represents a base event type that is used throughout signal, in event handlers you are able to use this information if needs be.
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

/// Messages processed by the Signal context.
pub opaque type ContextMessage(aggregate, command, event) {
  GetLogger(
    reply: process.Subject(Result(process.Subject(TelemetryMessage), String)),
  )
  SetLogger(process.Subject(TelemetryMessage))
  GetStore(
    reply: process.Subject(Result(process.Subject(StoreMessage(event)), String)),
  )
  SetStore(process.Subject(StoreMessage(event)))
  GetBus(
    reply: process.Subject(Result(process.Subject(BusMessage(event)), String)),
  )
  SetBus(process.Subject(BusMessage(event)))
  GetAggregatePool(
    reply: process.Subject(
      Result(process.Subject(PoolMessage(aggregate, command, event)), String),
    ),
  )
  SetAggregatePool(Pool(aggregate, command, event))
  ShutdownSignal
}

/// A base signal process which supervises the behind the scenes stuff and exposes some functionality.
/// 
///
pub opaque type Signal(aggregate, command, event) {
  Signal(process.Subject(ContextMessage(aggregate, command, event)))
}

/// An aggregate is an actor managed by signal that holds the state, processes commands and events.
/// 
/// You can send messasges to this aggregate and interact with it, but signal provides a number of pre-built functions to help with that.
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
/// pub fn handle_post_commands(notify: NotificationService) -> signal.CommandHandler(Post, PostCommands, PostEvents) {
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

/// When implementing a custom persistance layer, signal expects an actor that handles these messages
/// 
/// - GetStoredEvents: used for hydrating aggregates from storage
/// - IsIdentityAvailable: used to ensure duplicate ids cannot be created
/// - StoreEvents: used to persist a list of new events
/// - ShutdownPersistanceLayer: helper to let you shut down your actor, signal will not trigger this message
/// 
/// > ⚠️ Persistance actor has to report the result of the StoreEvents message in form of a PersistanceState event. This allows signal to handle a write ahead log and batch event storage operations. 
/// 
pub type StoreMessage(event) {
  GetStoredEvents(process.Subject(Result(List(Event(event)), String)), String)
  IsIdentityAvailable(process.Subject(Result(Bool, String)), String)
  StoreEvent(Event(event))
  ShutdownPersistanceLayer
}

/// Subscribers are triggered on **all** events produced by all aggregates, and serve as a great way to extend your system.
/// 
/// > Subscribers cannot modify or produce events.
/// 
/// These are generally great for creating different read models of your data, reporting, and reacting to certain events. 
///  
/// 
pub type Subscriber(state, event) {
  Consumer(process.Subject(ConsumerMessage(state, event)))
}

/// Consumers are actors that should receive and handle these messages.
/// 
/// - Consume: is the only message triggered by signal, and it is triggered on all events processed by the service
/// 
/// Other messages are there for user convenience.
/// 
pub type ConsumerMessage(state, event) {
  Consume(Event(event))
  GetConsumerState(reply: process.Subject(state))
  ShutdownConsumer
}

/// Configures the internals of an signal service.
///
pub opaque type SignalConfig(aggregate, state, command, event) {
  SignalConfig(
    aggregate: AggregateConfig(aggregate, command, event),
    persistance_handler: Option(process.Subject(StoreMessage(event))),
    subscribers: List(Subscriber(state, event)),
    pool_size: Int,
    custom_logger: Option(process.Subject(TelemetryMessage)),
    log_info: Bool,
    log_debug: Bool,
  )
}

/// Configures the aggregate processed by the signal service.
///
pub type AggregateConfig(aggregate, command, event) {
  AggregateConfig(
    initial_state: aggregate,
    command_handler: CommandHandler(aggregate, command, event),
    event_handler: EventHandler(aggregate, event),
  )
}

/// Simple message interface for logging events.
/// 
/// The template string is separated with | and is used to format the message.
/// It can be populated with the telemetry event data using a helper function format_telemetry_message.
/// 
pub type TelemetryMessage {
  Report(event: TelemetryEvent, template: String)
  ShutdownTelemetry
}

/// Telemetry events produced by signal, these can be used for logging, metric collection and tracing
/// 
pub type TelemetryEvent {
  PoolCreatingAggregate(aggregate_id: String)
  PoolCreatedAggregate(aggregate_id: String)
  PoolCannotCreateAggregateWithId(aggregate_id: String)
  PoolHydratingAggregate(aggregate_id: String)
  PoolHydratedAggregate(aggregate_id: String)
  PoolAggregateNotFound(aggregate_id: String)
  PoolRebalancingStarted(size: Int)
  PoolEvictedAggregate(aggregate_id: String)
  PoolRebalancingCompleted(new_size: Int)
  AggregateProcessingCommand(command_name: String, aggregate_id: String)
  AggregateProcessedCommand(command_name: String, aggregate_id: String)
  AggregateCommandProcessingFailed(command_name: String, aggregate_id: String)
  AggregateEventsProduced(event_name: String, aggregate_id: String)
  BusTriggeringSubscribers(event_name: String, subscribers: Int)
  BusSubscribersInformed(event_name: String, subscribers: Int)
  StorePushedEventToWriteAheadLog(event_name: String, pool_size: Int)
  StoreWriteAheadLogSizeWarning(pool_size: Int)
  StoreSubmittedBatchForPersistance(batch_size: Int)
  StorePersistanceCompleted(processed: Int, wal: Int)
}

/// Just a basic log severity model
/// 
pub type LogLevel {
  LogDebug
  LogInfo
  LogWarning
  LogError
}

// --------------------------- Exported functions ------------------------------

/// This is a configuration object that lets you set up your signal instance.
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
/// let store = signal.configure(aggregate_config)
/// |> signal.with_persistance_layer(my_storage)
/// |> signal.with_subscriber(my_notification_client)
/// |> signal.with_subscriber(my_metrics_counter)
/// |> signal.start()
/// ```
pub fn configure(
  agg: AggregateConfig(aggregate, command, event),
) -> SignalConfig(aggregate, state, command, event) {
  SignalConfig(
    aggregate: agg,
    persistance_handler: None,
    subscribers: [],
    pool_size: 100,
    custom_logger: None,
    log_info: True,
    log_debug: True,
  )
}

/// Subscribers can be one-of tasks (policies) or actors (consumers) that consume events generated by the aggregate.
/// They are called for each event produced by all aggregates.
///  
/// This is a great way of projecting state in a very specific way. Think of it as letting you create different read models of your data, or trigger some other specifics when an event is generated.
///
/// You can even use this method to trigger commands to your other aggregates, but be careful, that can make it difficult to track the state of you application!
///
/// *Example consumer:*
/// ```gleam
/// fn event_counter( message: signal.ConsumerMessage(MyBlogEvent), event_count: Int ) {
///   case messasge {
///     ShutdownConsumer -> actor.stop(process.Normal)
///     Consume(signal.Event(_)) -> actor.continue(event_count + 1)
///     GetConsumerState(s) -> {
///       process.send(s, event_count)
///       actor.continue(event_count)
///     }
///   }
/// } 
/// ```
/// There are a few things to note about Consumers:
/// - Signal will not start or stop your consumers, their lifetime is in your control.
/// - Signal will ignore any returned data
/// - Your actor should accept the messages which are actually the Events you defined at configuration time
/// 
pub fn with_subscriber(
  config: SignalConfig(aggregate, state, command, event),
  sub: Subscriber(state, event),
) -> SignalConfig(aggregate, state, command, event) {
  SignalConfig(..config, subscribers: [sub, ..config.subscribers])
}

/// Configures signal to store events using a particular persistance layer.
/// 
/// Signal will default to an **in-memory store** which is recommended for development.
/// 
/// WIP - I am working on some persistance layers, but for now, you can bring your own, or play around with in-memory persistance.
/// 
pub fn with_persistance_layer(
  config: SignalConfig(aggregate, state, command, event),
  persist: process.Subject(StoreMessage(event)),
) -> SignalConfig(aggregate, state, command, event) {
  SignalConfig(..config, persistance_handler: Some(persist))
}

/// Defines the maximum number of aggregates kept in memory. **Defaults to 100**,
/// lower it if you desire lower memory consumption, increase it if you desire higher performance.
/// 
/// When an aggregate which is not in the pool is requested, signal has to rebuild it from events in the database.
/// 
/// > ⚠️ **Large aggregates** that contain a lot of data are an **anti-pattern** in event sourcing, instead of lowering the pool size,
/// > you might want to consider breaking up your aggregate and redesigning it, or storing some data using a different persistance method.
/// 
pub fn with_pool_size_limit(
  config: SignalConfig(aggregate, state, command, event),
  aggregates_in_memory: Int,
) {
  SignalConfig(..config, pool_size: aggregates_in_memory)
}

/// Allows for custom logging of telemetry events.
/// 
pub fn with_custom_logger(
  config: SignalConfig(aggregate, state, command, event),
  logger: process.Subject(TelemetryMessage),
) -> SignalConfig(aggregate, state, command, event) {
  SignalConfig(..config, custom_logger: Some(logger))
}

/// Disables info level logging for the **default logger**.
/// 
/// > ⚠️ this setting does not affect custom loggers.
/// 
pub fn without_info_logging(
  config: SignalConfig(aggregate, state, command, event),
) -> SignalConfig(aggregate, state, command, event) {
  SignalConfig(..config, log_info: False)
}

/// Disables debug level logging for the **default logger**.
/// 
/// > ⚠️ this setting does not affect custom loggers.
/// 
pub fn without_debug_logging(
  config: SignalConfig(aggregate, state, command, event),
) -> SignalConfig(aggregate, state, command, event) {
  SignalConfig(..config, log_debug: False)
}

/// Starts the signal services and returns a subject used to interact with the event store.
/// 
pub fn start(config: SignalConfig(aggregate, state, command, event)) {
  signal_init(config)
}

/// Use this function to retrieve a particular aggregate from the signal event store. This will return a subject which can then be used to interact with state of you aggregate, or process further commands.
/// 
/// *Command handling example:*
/// ```gleam
/// let result = signal.aggregate(em, "how-to-gleam")
/// |> signal.handle_command(CommentOnPost("how-to-gleam"))
/// ```
///
/// *Getting state example:*
/// ```gleam
/// let post = signal.aggregate(em, "how-to-gleam")
/// |> signal.get_state()
/// ```
pub fn aggregate(
  signal: process.Subject(ContextMessage(aggregate, command, event)),
  id: String,
) -> Result(Aggregate(aggregate, command, event), String) {
  use pool <- result.try(process.call(
    signal,
    GetAggregatePool(_),
    process_call_timeout,
  ))
  process.call(pool, GetAggregate(_, id), process_call_timeout)
}

/// Creates a new aggregate with a given ID.
/// 
/// The ID needs to be unique, otherwise creation will fail.
/// 
pub fn create(
  signal: process.Subject(ContextMessage(aggregate, command, event)),
  id: String,
) -> Result(Aggregate(aggregate, command, event), String) {
  use pool <- result.try(process.call(
    signal,
    GetAggregatePool(_),
    process_call_timeout,
  ))
  process.call(pool, CreateAggregate(_, id), process_call_timeout)
}

/// Use this function to have your aggregate process a command.
/// 
/// ```gleam
/// let result = signal.aggregate(em, "how-to-gleam")
/// |> signal.handle_command(CreatePost("how-to-gleam"))
/// ```
/// 
pub fn handle_command(
  agg: Aggregate(aggregate, command, event),
  command: command,
) -> Result(aggregate, String) {
  process.call(agg, HandleCommand(_, command), process_call_timeout)
}

/// Use this function to get the current state of your aggregate.
/// 
/// ```gleam
/// let post = signal.aggregate(em, "how-to-gleam")
/// |> signal.get_state()
/// ```
pub fn get_state(agg: Aggregate(aggregate, command, event)) -> aggregate {
  process.call(agg, State(_), process_call_timeout)
}

/// Gets the id of the aggregate actor.
/// 
pub fn get_id(agg: Aggregate(aggregate, command, event)) -> String {
  process.call(agg, Identity(_), process_call_timeout)
}

/// Gets the current size of the aggregate pool in memory, mainly for testing.
/// 
pub fn get_current_pool_size(
  signal: process.Subject(ContextMessage(aggregate, command, event)),
) {
  use pool <- result.try(process.call(
    signal,
    GetAggregatePool(_),
    process_call_timeout,
  ))
  Ok(process.call(pool, PoolSize(_), process_call_timeout))
}

// -----------------------------------------------------------------------------
//                                    Signal                                      
// -----------------------------------------------------------------------------

type SignalService(aggregate, command, event) {
  SignalService(
    logger: Option(process.Subject(TelemetryMessage)),
    pool: Option(Pool(aggregate, command, event)),
    bus: Option(Bus(event)),
    store: Option(process.Subject(StoreMessage(event))),
  )
}

fn context_handler(
  msg: ContextMessage(aggregate, command, event),
  cfg: SignalService(aggregate, command, event),
) {
  case msg {
    GetLogger(s) -> send_and_continue(s, cfg.logger, cfg)
    GetStore(s) -> send_and_continue(s, cfg.store, cfg)
    GetBus(s) -> send_and_continue(s, cfg.bus, cfg)
    GetAggregatePool(s) -> send_and_continue(s, cfg.pool, cfg)
    SetLogger(s) -> actor.continue(SignalService(..cfg, logger: Some(s)))
    SetStore(s) -> actor.continue(SignalService(..cfg, store: Some(s)))
    SetBus(s) -> actor.continue(SignalService(..cfg, bus: Some(s)))
    SetAggregatePool(s) -> actor.continue(SignalService(..cfg, pool: Some(s)))
    ShutdownSignal -> actor.Stop(process.Normal)
  }
}

fn send_and_continue(
  s: process.Subject(Result(x, String)),
  msg: Option(x),
  state: z,
) {
  case msg {
    Some(m) -> process.send(s, Ok(m))
    None -> process.send(s, Error("No logger set"))
  }
  actor.continue(state)
}

fn signal_init(config: SignalConfig(aggregate, state, command, event)) {
  use signal <- result.try(actor.start(
    SignalService(None, None, None, None),
    context_handler,
  ))

  use logger <- result.try(case config.custom_logger {
    Some(logger) -> Ok(logger)
    None -> actor.start(Nil, console_logger(config.log_info, config.log_debug))
  })

  actor.send(signal, SetLogger(logger))

  let store = {
    case config.persistance_handler {
      Some(store) -> store
      None -> {
        let assert Ok(store) = actor.start([], in_memory_persistance_handler)
        store
      }
    }
  }

  actor.send(signal, SetStore(store))

  use bus <- result.try(actor.start(
    Nil,
    bus_handler(signal, config.subscribers),
  ))

  actor.send(signal, SetBus(bus))

  use pool <- result.try(actor.start(
    dict.new(),
    pool_handler(signal, config.aggregate, config.pool_size),
  ))

  actor.send(signal, SetAggregatePool(pool))

  Ok(signal)
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
        |> list.fold(aggregate, fn(agg, e) {
          apply_event(e, cfg.event_handler, agg)
        }),
      selector: process.new_selector(),
    )
  }
}

fn aggregate_handler(
  signal: process.Subject(ContextMessage(aggregate, command, event)),
  id: String,
  command_handler: CommandHandler(aggregate, command, event),
  event_handler: EventHandler(aggregate, event),
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
      HandleCommand(client, command) -> {
        log_telemetry(
          signal,
          AggregateProcessingCommand(type_name(command), id),
        )
        case command_handler(command, agg.state) {
          Ok(events) -> {
            let new_state =
              list.fold(events, agg, fn(agg, e) {
                update_aggregate(
                  AggregateUpdateContext(signal, id, event_handler, agg),
                  e,
                )
              })
            log_telemetry(
              signal,
              AggregateProcessedCommand(type_name(command), id),
            )
            case events {
              [] -> list.new()
              e ->
                list.map(e, fn(ev) {
                  log_telemetry(
                    signal,
                    AggregateEventsProduced(type_name(ev), id),
                  )
                })
            }
            process.send(client, Ok(new_state.state))
            actor.continue(new_state)
          }
          Error(msg) -> {
            log_telemetry(
              signal,
              AggregateCommandProcessingFailed(type_name(command), id),
            )
            process.send(client, Error(msg))
            actor.continue(agg)
          }
        }
      }
      ShutdownAggregate -> actor.Stop(process.Normal)
    }
  }
}

type AggregateUpdateContext(aggregate, command, event) {
  AggregateUpdateContext(
    signal: process.Subject(ContextMessage(aggregate, command, event)),
    id: String,
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
    event_name: type_name(event),
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
  let assert Ok(bus) = process.call(ctx.signal, GetBus(_), process_call_timeout)
  process.send(bus, PushEvent(event))
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
  signal: process.Subject(ContextMessage(aggregate, command, event)),
  config: AggregateConfig(aggregate, command, event),
  max_size: Int,
) {
  fn(
    operation: PoolMessage(aggregate, command, event),
    state: Dict(String, #(Aggregate(aggregate, command, event), Int)),
  ) {
    case operation {
      CreateAggregate(client, with_id) -> {
        log_telemetry(signal, PoolCreatingAggregate(with_id))
        let exists_in_store = store_has_aggregate(signal, with_id)
        let exists_in_pool = dict.has_key(state, with_id)

        case exists_in_store, exists_in_pool {
          False, False -> {
            case start_aggregate(signal, config, with_id, []) {
              Ok(agg) -> {
                process.send(client, Ok(agg))
                log_telemetry(signal, PoolCreatedAggregate(with_id))
                actor.continue(
                  dict.insert(
                    evict_aggregates_workflow(signal, max_size, state),
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
            log_telemetry(signal, PoolCannotCreateAggregateWithId(with_id))
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
            signal,
            start_aggregate(signal, config, id, _),
            state,
            id,
          )
        {
          Ok(aggregate) -> {
            dict.insert(state, id, #(aggregate, dict.size(state) + 1))
            process.send(client, Ok(aggregate))
          }
          Error(msg) -> {
            log_telemetry(signal, PoolAggregateNotFound(id))
            process.send(client, Error(msg))
          }
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
  signal: process.Subject(ContextMessage(aggregate, command, event)),
  max_size: Int,
  state: Dict(String, #(Aggregate(aggregate, command, event), Int)),
) {
  // Happens before insertion of aggregate into pool, hence - 1
  case dict.size(state) >= max_size {
    True -> {
      log_telemetry(signal, PoolRebalancingStarted(max_size))
      let eviction_list =
        dict.to_list(state)
        |> list.filter(fn(agg) {
          let #(_, #(_, position)) = agg
          position >= max_size
        })
        |> list.map(fn(agg) {
          let #(id, #(agg, _)) = agg
          process.send(agg, ShutdownAggregate)
          log_telemetry(signal, PoolEvictedAggregate(id))
          id
        })

      log_telemetry(
        signal,
        PoolRebalancingCompleted(list.length(eviction_list)),
      )
      dict.drop(state, eviction_list)
    }
    False -> state
  }
}

fn store_has_aggregate(
  signal: process.Subject(ContextMessage(aggregate, command, event)),
  key: String,
) {
  let response = {
    use store <- result.try(process.call(
      signal,
      GetStore(_),
      process_call_timeout,
    ))
    process.call(store, IsIdentityAvailable(_, key), process_call_timeout)
  }

  case response {
    Error(_) | Ok(False) -> True
    Ok(True) -> False
  }
}

fn gather_aggregate(
  signal: process.Subject(ContextMessage(aggregate, command, event)),
  aggregate_initializer: fn(List(Event(event))) ->
    Result(Aggregate(aggregate, command, event), String),
  dict: Dict(String, #(Aggregate(aggregate, command, event), Int)),
  id: String,
) {
  case dict.get(dict, id) {
    Ok(#(value, _)) -> Ok(value)
    Error(_) -> gather_aggregate_from_store(signal, aggregate_initializer, id)
  }
}

fn gather_aggregate_from_store(
  signal: process.Subject(ContextMessage(aggregate, command, event)),
  aggregate_initializer: fn(List(Event(event))) ->
    Result(Aggregate(aggregate, command, event), String),
  id: String,
) {
  log_telemetry(signal, PoolHydratingAggregate(id))
  let result = {
    use store <- result.try(process.call(
      signal,
      GetStore(_),
      process_call_timeout,
    ))
    process.call(store, GetStoredEvents(_, id), process_call_timeout)
  }
  case result {
    Error(msg) -> Error(msg)
    Ok(events) -> {
      log_telemetry(signal, PoolHydratedAggregate(id))
      aggregate_initializer(events)
    }
  }
}

fn start_aggregate(
  signal: process.Subject(ContextMessage(aggregate, command, event)),
  config: AggregateConfig(aggregate, command, event),
  id: String,
  events: List(Event(event)),
) {
  case
    actor.start_spec(actor.Spec(
      aggregate_init(events, config),
      5,
      aggregate_handler(
        signal,
        id,
        config.command_handler,
        config.event_handler,
      ),
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

fn bus_handler(
  signal: process.Subject(ContextMessage(aggregate, command, event)),
  subscribers: List(Subscriber(state, event)),
) {
  fn(message: BusMessage(event), _state: Nil) {
    case message {
      PushEvent(event) -> {
        notify_store(signal, event)
        notify_subscribers(signal, event, subscribers)
        actor.continue(Nil)
      }
      ShutdownBus -> actor.Stop(process.Normal)
    }
  }
}

fn notify_subscribers(
  signal: process.Subject(ContextMessage(aggregate, command, event)),
  event: Event(event),
  consumers: List(Subscriber(state, event)),
) {
  log_telemetry(
    signal,
    BusTriggeringSubscribers(event.event_name, list.length(consumers)),
  )

  case consumers {
    [] -> Nil
    [Consumer(s)] -> process.send(s, Consume(event))
    [Consumer(s), ..rest] -> {
      process.send(s, Consume(event))
      notify_subscribers(signal, event, rest)
    }
  }

  log_telemetry(
    signal,
    BusSubscribersInformed(event.event_name, list.length(consumers)),
  )
}

fn notify_store(
  signal: process.Subject(ContextMessage(aggregate, command, event)),
  event: Event(event),
) {
  let assert Ok(store) = process.call(signal, GetStore(_), process_call_timeout)
  process.send(store, StoreEvent(event))
}

// -----------------------------------------------------------------------------
//                         In memory persistance layer                          
// -----------------------------------------------------------------------------

/// Only public for testing purposes, you do not need to use this, it is a signal default.
/// 
pub fn in_memory_persistance_handler(
  message: StoreMessage(event),
  state: List(Event(event)),
) {
  case message {
    GetStoredEvents(s, aggregate_id) -> {
      case list.any(state, fn(e) { e.aggregate_id == aggregate_id }) {
        True ->
          process.send(
            s,
            Ok(list.filter(state, fn(e) { e.aggregate_id == aggregate_id })),
          )
        False -> process.send(s, Error("Aggregate not found"))
      }
      actor.continue(state)
    }
    IsIdentityAvailable(s, aggregate_id) -> {
      case list.all(state, fn(e) { e.aggregate_id != aggregate_id }) {
        True -> process.send(s, Ok(True))
        False -> process.send(s, Ok(False))
      }

      actor.continue(state)
    }
    StoreEvent(event) ->
      actor.continue([event, ..list.reverse(state)] |> list.reverse())
    ShutdownPersistanceLayer -> actor.Stop(process.Normal)
  }
}

// -----------------------------------------------------------------------------
//                                  Telemetry                                   
// -----------------------------------------------------------------------------

/// Formats a telemetry message using a template string and telemetry event data.
/// 
pub fn format_telemetry_message(data: TelemetryEvent, template: String) {
  list.interleave([string.split(template, "|"), telemetry_to_string_list(data)])
  |> string.concat()
}

fn telemetry_to_string_list(ev: TelemetryEvent) {
  case ev {
    PoolCreatingAggregate(id) -> [id]
    PoolCreatedAggregate(id) -> [id]
    PoolCannotCreateAggregateWithId(id) -> [id]
    PoolHydratingAggregate(id) -> [id]
    PoolHydratedAggregate(id) -> [id]
    PoolAggregateNotFound(id) -> [id]
    PoolRebalancingStarted(size) -> [int.to_string(size)]
    PoolEvictedAggregate(id) -> [id]
    PoolRebalancingCompleted(size) -> [int.to_string(size)]
    AggregateProcessingCommand(a, b) -> [a, b]
    AggregateProcessedCommand(a, b) -> [a, b]
    AggregateCommandProcessingFailed(a, b) -> [a, b]
    AggregateEventsProduced(a, b) -> [a, b]
    BusTriggeringSubscribers(a, b) -> [a, int.to_string(b)]
    BusSubscribersInformed(a, b) -> [a, int.to_string(b)]
    StorePushedEventToWriteAheadLog(a, b) -> [a, int.to_string(b)]
    StoreWriteAheadLogSizeWarning(pool_size) -> [int.to_string(pool_size)]
    StoreSubmittedBatchForPersistance(batch_size) -> [int.to_string(batch_size)]
    StorePersistanceCompleted(a, b) -> [int.to_string(a), int.to_string(b)]
  }
}

/// Default logging level for telemetry events, when implementing a custom logger, you can use this to filter out events.
/// 
pub fn telemetry_log_level(ev: TelemetryEvent) {
  case ev {
    PoolCreatingAggregate(_) -> LogDebug
    PoolCreatedAggregate(_) -> LogDebug
    PoolCannotCreateAggregateWithId(_) -> LogError
    PoolHydratingAggregate(_) -> LogDebug
    PoolHydratedAggregate(_) -> LogDebug
    PoolAggregateNotFound(_) -> LogError
    PoolRebalancingStarted(_) -> LogDebug
    PoolEvictedAggregate(_) -> LogDebug
    PoolRebalancingCompleted(_) -> LogDebug
    AggregateProcessingCommand(_, _) -> LogInfo
    AggregateProcessedCommand(_, _) -> LogInfo
    AggregateCommandProcessingFailed(_, _) -> LogError
    AggregateEventsProduced(_, _) -> LogDebug
    BusTriggeringSubscribers(_, _) -> LogDebug
    BusSubscribersInformed(_, _) -> LogDebug
    StorePushedEventToWriteAheadLog(_, _) -> LogDebug
    StoreWriteAheadLogSizeWarning(_) -> LogWarning
    StoreSubmittedBatchForPersistance(_) -> LogDebug
    StorePersistanceCompleted(_, _) -> LogDebug
  }
}

fn log_telemetry(
  signal: process.Subject(ContextMessage(aggregate, command, event)),
  event: TelemetryEvent,
) {
  case process.call(signal, GetLogger(_), process_call_timeout) {
    Ok(logger) ->
      process.send(
        logger,
        Report(event, case event {
          PoolCreatingAggregate(_) -> "Creating aggregate |"
          PoolCreatedAggregate(_) -> "Pool created aggregate |"
          PoolCannotCreateAggregateWithId(_) ->
            "Cannot create aggregate |, that id is already taken!"
          PoolHydratingAggregate(_) -> "Hydrating aggregate |"
          PoolHydratedAggregate(_) -> "Hydrated aggregate |"
          PoolAggregateNotFound(_) -> "Aggregate | not found"
          PoolRebalancingStarted(_) -> "Rebalancing pool to, from size |"
          PoolEvictedAggregate(_) -> "Evicted aggregate |"
          PoolRebalancingCompleted(_) -> "Rebalancing completed, new size |"
          AggregateProcessingCommand(_, _) ->
            "Processing command | with aggregate |"
          AggregateProcessedCommand(_, _) ->
            "Command | processed by aggregate |"
          AggregateCommandProcessingFailed(_, _) ->
            "Command | processing failed by aggregate |"
          AggregateEventsProduced(_, _) -> "Events | produced by aggregate: |"
          BusTriggeringSubscribers(_, _) -> "Sending event | to | subscribers"
          BusSubscribersInformed(_, _) -> "Sent event | to | subscribers"
          StorePushedEventToWriteAheadLog(_, _) ->
            "Pushed event | to write ahead log, wal size |"
          StoreWriteAheadLogSizeWarning(_) ->
            "Wal is overflowing! | events are waiting to be persisted!"
          StoreSubmittedBatchForPersistance(_) ->
            "Submitted | events for persistance"
          StorePersistanceCompleted(_, _) ->
            "Persisted | events, | events have not yet been reported persisted."
        }),
      )
    _ -> Nil
  }
}

// -----------------------------------------------------------------------------
//                               Console logger                                 
// -----------------------------------------------------------------------------

/// A simple console logger that logs telemetry events to the console.
/// 
pub fn console_logger(log_info: Bool, log_debug: Bool) {
  fn(message: TelemetryMessage, _: Nil) {
    case message {
      Report(event, template) -> {
        let log_level = telemetry_log_level(event)
        let prefix = "SIGNAL --- " <> type_name(event) <> " --- "
        case log_level {
          LogError ->
            io.print_error(prefix <> format_telemetry_message(event, template))
          LogWarning ->
            io.println(prefix <> format_telemetry_message(event, template))
          LogInfo if log_info ->
            io.println(prefix <> format_telemetry_message(event, template))
          LogDebug if log_debug ->
            io.println(prefix <> format_telemetry_message(event, template))
          _ -> Nil
        }

        actor.continue(Nil)
      }
      ShutdownTelemetry -> actor.Stop(process.Normal)
    }
  }
}

// ----------------------------- Various helpers -------------------------------

fn type_name(v: any) {
  let str =
    v
    |> string.inspect()
    |> string.split_once("(")

  case str {
    Ok(#(type_string, _)) -> type_string
    Error(_) -> "Unknown"
  }
}
