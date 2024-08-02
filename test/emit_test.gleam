import gleam/io
import gleeunit
import gleeunit/should
import simulation

pub fn main() {
  gleeunit.main()

  io.debug(simulation.new(simulation.TenAggregates))
}

pub fn creates_simulation_with_fake_data_test() {
  let sim = simulation.new(simulation.TenAggregates)
  io.debug(sim)
  should.be_ok(Ok(Nil))
}
