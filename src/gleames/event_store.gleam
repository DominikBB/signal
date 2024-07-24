pub type EventStore

pub type Configuration(
  has_persistance,
  has_publishing,
  has_pool_size,
  aggregate,
  command,
  event,
) {
  Configuration(
    service_name: String,
    registered_aggregates: List(
      AggregateConfiguration(aggregate, command, event),
    ),
    persistance_handler: Option(handlers.PersistanceHandler(event)),
    publishing_handler: Option(handlers.PublishingHandler(event)),
  )
}

pub type WithPersistanceHandler

pub type WithPublishingHandler

pub type WithPoolSize

pub type AggregateConfiguration(aggregate, command, event) {
  AggregateConfiguration(
    name: String,
    initial_state: aggregate,
    command_handler: handlers.CommandHandler(aggregate, command, event),
    event_handler: handlers.EventHandler(aggregate, event),
  )
}

pub fn register_aggregate(
  event_store_config: Configuration,
  aggregate_config: AggregateConfiguration,
) {
  Configuration(
    ..event_store_config,
    aggregate_config: [
      aggregate_config,
      ..event_store_config.registered_aggregates
    ],
  )
}

pub fn create(event_store_config: Configuration(WithPersistance)) {
  todo
}
