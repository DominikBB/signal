import emit
import fixture
import gleam/io
import gleam/list
import gleeunit
import gleeunit/should
import simulation

pub fn main() {
  gleeunit.main()
}

pub fn new_simulation_creates_test_data() {
  let sim = simulation.new(simulation.OneAggregate, simulation.TestCommands)
  should.equal(list.length(sim.list_of_aggregates), 1)

  let assert Ok(agg) = list.first(sim.list_of_aggregates)
  should.be_true(list.length(agg.commands) >= 1)
}

pub fn processing_commands_produces_events_and_mutates_state_test() {
  let sim = simulation.new(simulation.OneAggregate, simulation.TestCommands)
  should.equal(list.length(sim.list_of_aggregates), 1)
  let sut = set_up_emit() |> emit.start()
  let assert Ok(agg) = list.first(sim.list_of_aggregates)
}

fn set_up_emit() {
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
}
