import emit
import fixture
import gleam/erlang/process
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/result
import gleam/set
import gleeunit
import gleeunit/should
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
    let assert Ok(retrieved_agg) = emit.aggregate(sut, agg.id)
    emit.get_id(retrieved_agg)
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
      emit.aggregate(sut, agg.id) |> result.map(emit.get_state(_))

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

  list.map(sim.list_of_aggregates, fn(agg) {
    let assert Ok(events) =
      process.call(store, emit.GetStoredEvents(_, agg.id), 5)

    list.length(events)
    |> should.equal(1)
  })
}

pub fn event_bus_borodcasts_events_to_subscribers_test() {
  let sim = simulation.new(simulation.ThreeAggregates, simulation.TestCommands)
  let #(sut, event_counter, aggregate_counter, _) = set_up_emit()
  let assert Ok(_) = create_aggregates(sut, sim)
  let assert Ok(_) = handle_simulation_commands(sut, sim, option.Some(1))

  process.call(event_counter, emit.GetConsumerState(_), 5)
  |> should.equal(3)

  process.call(aggregate_counter, emit.GetConsumerState(_), 5)
  |> should.equal(3)
}

pub fn aggregate_pool_evicts_aggregates_from_memory_test() {
  let sim = simulation.new(simulation.TenAggregates, simulation.TestCommands)
  let #(sut, _, _, _) = set_up_emit()
  let assert Ok(_) = create_aggregates(sut, sim)

  list.length(sim.list_of_aggregates) |> should.equal(10)

  emit.get_current_pool_size(sut)
  |> should.equal(5)
}

// -----------------------------------------------------------------------------
//                                 Test setup                                   
// -----------------------------------------------------------------------------

fn set_up_emit() {
  let assert Ok(persistance) = actor.start([], test_persistance_handler)
  let assert Ok(event_counter) = actor.start(0, event_count_subscriber)
  let assert Ok(aggregate_counter) =
    actor.start(set.new(), unique_aggregate_counter_subscriber)

  let assert Ok(emit) =
    emit.configure(emit.AggregateConfig(
      initial_state: fixture.InProgressRoute(
        id: "",
        payload: [],
        delivered_volume: 0.0,
        failed_volume: 0.0,
      ),
      command_handler: fixture.command_handler(),
      event_handler: fixture.event_handler(),
    ))
    |> emit.with_pool_size_limit(5)
    |> emit.with_persistance_layer(persistance)
    |> emit.with_subscriber(emit.Consumer(event_counter))
    |> emit.with_subscriber(emit.Consumer(aggregate_counter))
    |> emit.start()

  #(emit, event_counter, aggregate_counter, persistance)
}

fn create_aggregates(
  sut: emit.Emit(
    fixture.DeliveryRoute,
    fixture.DeliveryCommand,
    fixture.DeliveryEvent,
  ),
  sim: simulation.Simulation(fixture.DeliveryCommand, fixture.DeliveryEvent),
) {
  result.all(
    list.map(sim.list_of_aggregates, fn(agg) { emit.create(sut, agg.id) }),
  )
}

fn handle_simulation_commands(
  sut: emit.Emit(
    fixture.DeliveryRoute,
    fixture.DeliveryCommand,
    fixture.DeliveryEvent,
  ),
  sim: simulation.Simulation(fixture.DeliveryCommand, fixture.DeliveryEvent),
  limit: option.Option(Int),
) {
  result.all(
    list.map(sim.list_of_aggregates, fn(agg) {
      let assert Ok(sub_agg) = emit.aggregate(sut, agg.id)
      process_commands(sub_agg, agg.commands, limit)
    }),
  )
}

fn process_commands(
  sut: emit.Aggregate(
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

      case emit.handle_command(sut, command), quirk {
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
  message: emit.PersistanceInterface(event),
  state: List(emit.Event(event)),
) {
  case message {
    emit.GetStoredEvents(s, aggregate_id) -> {
      process.send(
        s,
        Ok(list.filter(state, fn(e) { e.aggregate_id == aggregate_id })),
      )
      actor.continue(state)
    }
    emit.IsIdentityAvailable(s, aggregate_id) -> {
      case list.any(state, fn(e) { e.aggregate_id == aggregate_id }) {
        True -> process.send(s, Ok(True))
        False -> process.send(s, Ok(False))
      }

      actor.continue(state)
    }
    emit.StoreEvents(events) -> actor.continue(list.append(state, events))
    emit.ShutdownPersistanceLayer -> actor.Stop(process.Normal)
  }
}

fn event_count_subscriber(
  message: emit.ConsumerMessage(Int, event),
  event_count: Int,
) {
  case message {
    emit.Consume(_) -> actor.continue(event_count + 1)
    emit.GetConsumerState(s) -> {
      process.send(s, event_count)
      actor.continue(event_count)
    }
    emit.ShutdownConsumer -> actor.Stop(process.Normal)
  }
}

fn unique_aggregate_counter_subscriber(
  message: emit.ConsumerMessage(Int, event),
  aggregate_ids: set.Set(String),
) {
  case message {
    emit.Consume(e) -> actor.continue(set.insert(aggregate_ids, e.aggregate_id))
    emit.GetConsumerState(s) -> {
      process.send(s, set.size(aggregate_ids))
      actor.continue(aggregate_ids)
    }
    emit.ShutdownConsumer -> actor.Stop(process.Normal)
  }
}
