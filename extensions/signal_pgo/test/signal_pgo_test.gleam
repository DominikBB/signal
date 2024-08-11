import gleeunit
import gleeunit/should
import signal_pgo

pub fn main() {
  gleeunit.main()
}

pub fn comlies_with_signal_requirements_test() {
  todo
  // let persistance =
  //   signal_pgo.start(pgo.Config(
  //     host: "localhost",
  //     port: 5500,
  //     database: "signal_dev",
  //     username: "postgres",
  //     password: "postgres",
  //     pool_size: 10,
  //   ))
  // let assert Ok(persistance) =
  //   actor.start([], signal.in_memory_persistance_handler)
  // result.all(testing.persistance_layer_complies_with_signal(persistance))
  // |> should.be_ok()
}
