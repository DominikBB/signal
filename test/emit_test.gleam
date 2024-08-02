import gleam/io
import gleam/list
import gleeunit
import gleeunit/should
import simulation

pub fn main() {
  gleeunit.main()
}

pub fn creates_simulation_with_fake_data_test() {
  let sim = simulation.new(simulation.OneAggregate, simulation.TestCommands)
  io.debug(sim)
  should.be_ok(Ok(Nil))
}
