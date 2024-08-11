import gleam/dynamic
import gleam/json.{array, int, object, string}
import gleam/option
import gleam/pgo
import gleam/result
import gleeunit
import gleeunit/should
import signal/testing
import signal_pgo

pub fn main() {
  gleeunit.main()
}

fn test_event_encoder(event: testing.PersistanceTestEvent) {
  case event {
    testing.SimpleEvent(str) -> {
      object([#("some", string(str))])
      |> json.to_string
    }
    testing.ComplexEvent(str, arr) -> {
      object([#("some", string(str)), #("list", array(arr, of: int))])
      |> json.to_string
    }
  }
}

fn test_event_decoder(event_name: String, event: String) {
  case event_name {
    "SimpleEvent" -> {
      let decoder =
        dynamic.decode1(
          testing.SimpleEvent,
          dynamic.field("some", dynamic.string),
        )

      case json.decode(event, decoder) {
        Ok(event) -> event
        Error(_) -> panic as "error"
      }
    }
    "ComplexEvent" -> {
      let decoder =
        dynamic.decode2(
          testing.ComplexEvent,
          dynamic.field("some", dynamic.string),
          dynamic.field("list", dynamic.list(dynamic.int)),
        )

      case json.decode(event, decoder) {
        Ok(event) -> event
        Error(_) -> panic as "error"
      }
    }
    _ -> panic as "Unknown event"
  }
}

pub fn comlies_with_signal_requirements_test() {
  let pgo_config =
    pgo.Config(
      ..pgo.default_config(),
      host: "localhost",
      port: 5500,
      database: "signal_dev",
      user: "postgres",
      pool_size: 2,
    )

  cleanup_db(pgo_config)

  let assert Ok(persistance) =
    signal_pgo.start(pgo_config, test_event_encoder, test_event_decoder)

  result.all(testing.persistance_layer_complies_with_signal(persistance))
  |> should.be_ok()
}

fn cleanup_db(pgo_config: pgo.Config) {
  let db = pgo.connect(pgo_config)
  let assert Ok(_) =
    "
    DROP TABLE IF EXISTS signal_event_store;
    "
    |> pgo.execute(db, [], dynamic.dynamic)
  pgo.disconnect(db)
}
