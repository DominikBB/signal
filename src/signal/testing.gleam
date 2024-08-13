import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/result
import signal

pub type PersistanceTestEvent {
  SimpleEvent(String)
  ComplexEvent(String, List(Int))
}

const test_events = [
  signal.Event(
    aggregate_id: "1",
    aggregate_version: 1,
    event_name: "SimpleEvent",
    data: SimpleEvent("simple"),
  ),
  signal.Event(
    aggregate_id: "2",
    aggregate_version: 1,
    event_name: "SimpleEvent",
    data: SimpleEvent("simple"),
  ),
  signal.Event(
    aggregate_id: "3",
    aggregate_version: 1,
    event_name: "SimpleEvent",
    data: SimpleEvent("simple"),
  ),
  signal.Event(
    aggregate_id: "1",
    aggregate_version: 2,
    event_name: "ComplexEvent",
    data: ComplexEvent("simple", [1, 2, 3]),
  ),
  signal.Event(
    aggregate_id: "2",
    aggregate_version: 2,
    event_name: "ComplexEvent",
    data: ComplexEvent("simple", [1, 2, 3]),
  ),
  signal.Event(
    aggregate_id: "3",
    aggregate_version: 2,
    event_name: "ComplexEvent",
    data: ComplexEvent("simple", [1, 2, 3]),
  ),
]

fn persistance_layer_stores_events(
  persistance_layer: process.Subject(signal.StoreMessage(PersistanceTestEvent)),
) {
  // Store events
  list.map(test_events, fn(event) {
    process.send(persistance_layer, signal.StoreEvent(event))
  })

  // Retrieve events
  use agg1 <- result.try(process.call(
    persistance_layer,
    signal.GetStoredEvents(_, "1"),
    100,
  ))
  use agg2 <- result.try(process.call(
    persistance_layer,
    signal.GetStoredEvents(_, "2"),
    100,
  ))
  use agg3 <- result.try(process.call(
    persistance_layer,
    signal.GetStoredEvents(_, "3"),
    100,
  ))

  let retrieved_event_count = list.length(list.flatten([agg1, agg2, agg3]))
  let test_event_count = list.length(test_events)

  // Assert events
  case retrieved_event_count == test_event_count {
    True -> Ok(Nil)
    _ ->
      Error(
        "Stored "
        <> int.to_string(test_event_count)
        <> " events, but retrieved "
        <> int.to_string(retrieved_event_count),
      )
  }
}

fn persistance_layer_retrieves_events_in_order(
  persistance_layer: process.Subject(signal.StoreMessage(PersistanceTestEvent)),
) {
  // Store events
  list.map(list.reverse(test_events), fn(event) {
    process.send(persistance_layer, signal.StoreEvent(event))
  })

  // Retrieve events
  use agg1 <- result.try(process.call(
    persistance_layer,
    signal.GetStoredEvents(_, "1"),
    100,
  ))

  case agg1 {
    [first, ..] if first.aggregate_version == 1 -> Ok(Nil)
    [first, ..] ->
      Error(
        "Events should be sorted in ascending order according to aggrerate version, but the first event has version "
        <> int.to_string(first.aggregate_version),
      )
    _ -> Error("No events retrieved, event though events were stored")
  }
}

fn persistance_layer_retrieves_only_events_for_aggregate(
  persistance_layer: process.Subject(signal.StoreMessage(PersistanceTestEvent)),
) {
  // Store events
  list.map(test_events, fn(event) {
    process.send(persistance_layer, signal.StoreEvent(event))
  })

  // Retrieve events
  use agg1 <- result.try(process.call(
    persistance_layer,
    signal.GetStoredEvents(_, "1"),
    100,
  ))

  case list.all(agg1, fn(event) { event.aggregate_id == "1" }) {
    True -> Ok(Nil)
    _ -> Error("Retrieved events for other aggregates!")
  }
}

fn persistance_layer_will_correctly_report_on_used_ids(
  persistance_layer: process.Subject(signal.StoreMessage(PersistanceTestEvent)),
) {
  // Store events
  list.map(test_events, fn(event) {
    process.send(persistance_layer, signal.StoreEvent(event))
  })

  // Retrieve events
  use used_ids <- result.try(process.call(
    persistance_layer,
    signal.IsIdentityAvailable(_, "1"),
    100,
  ))

  case used_ids {
    False -> Ok(Nil)
    _ ->
      Error(
        "Aggregate id 1 should be reported as taken, but it was reported as available!",
      )
  }
}

pub fn persistance_layer_complies_with_signal(
  persistance_layer: process.Subject(signal.StoreMessage(PersistanceTestEvent)),
) {
  [
    persistance_layer_stores_events(persistance_layer),
    persistance_layer_retrieves_events_in_order(persistance_layer),
    persistance_layer_retrieves_only_events_for_aggregate(persistance_layer),
    persistance_layer_will_correctly_report_on_used_ids(persistance_layer),
  ]
}
