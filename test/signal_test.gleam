import fixture
import gleam/erlang/process
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/result
import gleam/set
import gleeunit
import gleeunit/should
import signal.{type ContextMessage}
import signal/testing
import simulation

pub fn main() {
  gleeunit.main()
}

pub fn new_simulation_creates_test_data_test() {
  let sim = simulation.new(simulation.OneAggregate, simulation.TestCommands)
  should.equal(list.length(sim.list_of_aggregates), 1)

  let assert Ok(agg) = list.first(sim.list_of_aggregates)
  should.be_true(list.length(agg.commands) >= 1)
}

pub fn emit_creates_aggregates_test() {
  let sim = simulation.new(simulation.ThreeAggregates, simulation.TestCommands)
  let #(sut, _, _, _) = set_up_emit()

  let assert Ok(aggregates) = create_aggregates(sut, sim)

  list.length(aggregates)
  |> should.equal(3)
}

pub fn emit_retrieves_aggregates_test() {
  let sim = simulation.new(simulation.ThreeAggregates, simulation.TestCommands)
  let #(sut, _, _, _) = set_up_emit()
  let assert Ok(_) = create_aggregates(sut, sim)

  list.map(sim.list_of_aggregates, fn(agg) {
    let assert Ok(retrieved_agg) = signal.aggregate(sut, agg.id)
    signal.get_id(retrieved_agg)
    |> should.equal(agg.id)
  })
}

pub fn aggregate_processes_commands_and_mutates_state_test() {
  let sim = simulation.new(simulation.ThreeAggregates, simulation.TestCommands)
  let #(sut, _, _, _) = set_up_emit()
  let assert Ok(_) = create_aggregates(sut, sim)
  let assert Ok(_) = handle_simulation_commands(sut, sim, option.Some(2))

  list.map(sim.list_of_aggregates, fn(agg) {
    let assert Ok(retrieved_state) =
      signal.aggregate(sut, agg.id) |> result.map(signal.get_state(_))

    let assert [_, #(_, fixture.AssignPackages(assigned)), ..] = agg.commands

    retrieved_state.id
    |> should.equal(agg.id)

    list.length(retrieved_state.payload)
    |> should.equal(list.length(assigned))
  })
}

pub fn aggregate_processes_commands_and_emits_events_test() {
  let sim = simulation.new(simulation.ThreeAggregates, simulation.TestCommands)
  let #(sut, _, _, store) = set_up_emit()
  let assert Ok(_) = create_aggregates(sut, sim)
  let assert Ok(_) = handle_simulation_commands(sut, sim, option.Some(1))

  process.sleep(50)

  list.map(sim.list_of_aggregates, fn(agg) {
    let assert Ok(events) =
      process.call(store, signal.GetStoredEvents(_, agg.id), 50)

    list.length(events)
    |> should.equal(1)
  })
}

pub fn event_bus_borodcasts_events_to_subscribers_test() {
  let sim = simulation.new(simulation.ThreeAggregates, simulation.TestCommands)
  let #(sut, event_counter, aggregate_counter, _) = set_up_emit()
  let assert Ok(_) = create_aggregates(sut, sim)
  let assert Ok(_) = handle_simulation_commands(sut, sim, option.Some(1))

  process.sleep(50)

  process.call(event_counter, signal.GetConsumerState(_), 50)
  |> should.equal(3)

  process.call(aggregate_counter, signal.GetConsumerState(_), 50)
  |> should.equal(3)
}

pub fn aggregate_pool_evicts_aggregates_from_memory_test() {
  let sim = simulation.new(simulation.TenAggregates, simulation.TestCommands)
  let #(sut, _, _, _) = set_up_emit()
  let assert Ok(_) = create_aggregates(sut, sim)

  list.length(sim.list_of_aggregates) |> should.equal(10)

  signal.get_current_pool_size(sut)
  |> should.be_ok()
  |> should.equal(5)
}

pub fn in_memory_persistance_layer_fullfils_signal_requirements_test() {
  let assert Ok(persistance) =
    actor.start([], signal.in_memory_persistance_handler)
  result.all(testing.persistance_layer_complies_with_signal(persistance))
  |> should.be_ok()
}

pub fn events_generated_contain_correct_metadata_test() {
  let sim = simulation.new(simulation.ThreeAggregates, simulation.TestCommands)
  let #(sut, _, _, store) = set_up_emit()
  let assert Ok(_) = create_aggregates(sut, sim)
  let assert Ok(_) = handle_simulation_commands(sut, sim, option.Some(1))

  process.sleep(50)

  let assert Ok(agg) = list.first(sim.list_of_aggregates)

  let assert Ok(events) =
    process.call(store, signal.GetStoredEvents(_, agg.id), 50)

  let assert Ok(event) = list.first(events)

  event.aggregate_name |> should.equal("InProgressRoute")
  event.event_name |> should.equal("RouteCreated")
}

// -----------------------------------------------------------------------------
//                                 Test setup                                   
// -----------------------------------------------------------------------------

fn set_up_emit() {
  let assert Ok(logger) = actor.start([], test_logger)
  let assert Ok(persistance) = actor.start([], test_persistance_handler)
  let assert Ok(event_counter) = actor.start(0, event_count_subscriber)
  let assert Ok(aggregate_counter) =
    actor.start(set.new(), unique_aggregate_counter_subscriber)

  let assert Ok(signal) =
    signal.configure(signal.AggregateConfig(
      initial_state: fixture.InProgressRoute(
        id: "",
        payload: [],
        delivered_volume: 0.0,
        failed_volume: 0.0,
      ),
      command_handler: fixture.command_handler(),
      event_handler: fixture.event_handler(),
    ))
    |> signal.with_pool_size_limit(5)
    |> signal.with_persistance_layer(persistance)
    |> signal.with_subscriber(signal.Consumer(event_counter))
    |> signal.with_subscriber(signal.Consumer(aggregate_counter))
    |> signal.with_custom_logger(logger)
    |> signal.start()

  #(signal, event_counter, aggregate_counter, persistance)
}

fn create_aggregates(
  sut: process.Subject(
    ContextMessage(
      fixture.DeliveryRoute,
      fixture.DeliveryCommand,
      fixture.DeliveryEvent,
    ),
  ),
  sim: simulation.Simulation(fixture.DeliveryCommand, fixture.DeliveryEvent),
) {
  result.all(
    list.map(sim.list_of_aggregates, fn(agg) { signal.create(sut, agg.id) }),
  )
}

fn handle_simulation_commands(
  sut: process.Subject(
    ContextMessage(
      fixture.DeliveryRoute,
      fixture.DeliveryCommand,
      fixture.DeliveryEvent,
    ),
  ),
  sim: simulation.Simulation(fixture.DeliveryCommand, fixture.DeliveryEvent),
  limit: option.Option(Int),
) {
  result.all(
    list.map(sim.list_of_aggregates, fn(agg) {
      let assert Ok(sub_agg) = signal.aggregate(sut, agg.id)
      process_commands(sub_agg, agg.commands, limit)
    }),
  )
}

fn process_commands(
  sut: signal.Aggregate(
    fixture.DeliveryRoute,
    fixture.DeliveryCommand,
    fixture.DeliveryEvent,
  ),
  commands: List(
    #(option.Option(simulation.CommandQuirks), fixture.DeliveryCommand),
  ),
  limit: option.Option(Int),
) {
  let commands_to_handle = case limit {
    option.Some(n) -> list.take(commands, n)
    option.None -> commands
  }

  result.all(
    list.map(commands_to_handle, fn(cmd) {
      let #(quirk, command) = cmd
      case signal.handle_command(sut, command), quirk {
        Error(_), option.None -> Error(cmd)
        _, _ -> Ok(cmd)
      }
    }),
  )
}

// -----------------------------------------------------------------------------
//                                Test handlers                                 
// -----------------------------------------------------------------------------

fn test_persistance_handler(
  message: signal.StoreMessage(event),
  state: List(signal.Event(event)),
) {
  case message {
    signal.GetStoredEvents(s, aggregate_id) -> {
      process.send(
        s,
        Ok(list.filter(state, fn(e) { e.aggregate_id == aggregate_id })),
      )
      actor.continue(state)
    }
    signal.IsIdentityAvailable(s, aggregate_id) -> {
      case list.any(state, fn(e) { e.aggregate_id == aggregate_id }) {
        True -> process.send(s, Ok(False))
        False -> process.send(s, Ok(True))
      }

      actor.continue(state)
    }
    signal.StoreEvent(event) ->
      actor.continue([event, ..list.reverse(state)] |> list.reverse())
    signal.ShutdownPersistanceLayer -> actor.Stop(process.Normal)
  }
}

fn event_count_subscriber(
  message: signal.ConsumerMessage(Int, event),
  event_count: Int,
) {
  case message {
    signal.Consume(_) -> actor.continue(event_count + 1)
    signal.GetConsumerState(s) -> {
      process.send(s, event_count)
      actor.continue(event_count)
    }
    signal.ShutdownConsumer -> actor.Stop(process.Normal)
  }
}

fn unique_aggregate_counter_subscriber(
  message: signal.ConsumerMessage(Int, event),
  aggregate_ids: set.Set(String),
) {
  case message {
    signal.Consume(e) ->
      actor.continue(set.insert(aggregate_ids, e.aggregate_id))
    signal.GetConsumerState(s) -> {
      process.send(s, set.size(aggregate_ids))
      actor.continue(aggregate_ids)
    }
    signal.ShutdownConsumer -> actor.Stop(process.Normal)
  }
}

fn test_logger(
  message: signal.TelemetryMessage,
  state: List(signal.TelemetryEvent),
) {
  case message {
    signal.Report(event, _) -> {
      // io.debug(event)
      actor.continue([event, ..state] |> list.reverse())
    }
    signal.ShutdownTelemetry -> actor.Stop(process.Normal)
  }
}
