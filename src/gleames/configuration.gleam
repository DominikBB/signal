import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/supervisor
import gleames/handlers

pub opaque type Gleames(aggregate, command, event) {
  Gleames(Subject(Messages(aggregate)))
}

pub type Messages(aggregate) {
  GetAggregate(reply_with: Subject(Result(aggregate, String)), id: String)
  Shutdown
}

pub type Configuration(aggregate, command, event) {
  Configuration(
    service_name: String,
    aggregate: AggregateConfiguration(aggregate, command, event),
    persistance_handler: Option(handlers.PersistanceHandler(event)),
    subscribers: List(handlers.Subscriber(event)),
    pool_size: Option(Int),
  )
}

pub fn new(
  service_name: String,
  aggregate: AggregateConfiguration(aggregate, command, event),
) -> Configuration(aggregate, command, event) {
  Configuration(
    service_name: service_name,
    aggregate: aggregate,
    persistance_handler: None,
    subscribers: [],
    pool_size: None,
  )
}

pub fn with_persistance_layer(
  config: Configuration(aggregate, command, event),
  handler: handlers.PersistanceHandler(event),
) -> Configuration(aggregate, command, event) {
  Configuration(..config, persistance_handler: Some(handler))
}

pub fn register_event_subscriber(
  config: Configuration(aggregate, command, event),
  subscriber: handlers.Subscriber(event),
) -> Configuration(aggregate, command, event) {
  Configuration(..config, subscribers: [subscriber, ..config.subscribers])
}

pub fn start(
  config: Configuration(aggregate, command, event),
) -> Gleames(aggregate, command, event) {
  todo
  // let children = fn(children) {
  //   children
  //   |> supervisor.add(supervisor.worker(pool.start))
  //   |> supervisor.add(supervisor.worker(bus.start))
  //   |> supervisor.add(supervisor.worker(store.start))
  // }

  // supervisor.start(children)
}

pub type AggregateConfiguration(aggregate, command, event) {
  AggregateConfiguration(
    initial_state: aggregate,
    command_handler: handlers.CommandHandler(aggregate, command, event),
    event_handler: handlers.EventHandler(aggregate, event),
    shutdown_after_seconds: Option(Int),
  )
}

pub fn new_aggregate(
  initial_state: aggregate,
  command_handler: handlers.CommandHandler(aggregate, command, event),
  event_handler: handlers.EventHandler(aggregate, event),
  shutdown_after_seconds: Option(Int),
) -> AggregateConfiguration(aggregate, command, event) {
  AggregateConfiguration(
    initial_state: initial_state,
    command_handler: command_handler,
    event_handler: event_handler,
    shutdown_after_seconds: shutdown_after_seconds,
  )
}
