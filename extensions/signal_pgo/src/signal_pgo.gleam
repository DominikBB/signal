import gleam/dynamic
import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/pgo
import gleam/result
import signal

pub fn start(
  pgo_config: pgo.Config,
  event_encoder: fn(event) -> String,
  event_decoder: fn(String, String) -> event,
) {
  let db = pgo.connect(pgo_config)
  let assert Ok(_) = migrate(db)

  actor.start(Nil, pgo_handler(db, event_encoder, event_decoder))
}

fn migrate(db: pgo.Connection) {
  let assert Ok(_) =
    "
    CREATE TABLE IF NOT EXISTS signal_event_store (
        id SERIAL PRIMARY KEY,
        aggregate_id VARCHAR(255),
        aggregate_version INT,
        event_name VARCHAR(255),
        data TEXT
    );

    "
    |> pgo.execute(db, [], dynamic.dynamic)

  let assert Ok(_) =
    "
    CREATE INDEX IF NOT EXISTS idx_signal_events_aggregate_id ON signal_events (aggregate_id);
    "
    |> pgo.execute(db, [], dynamic.dynamic)
}

type PgoEvent {
  PgoEvent(
    aggregate_id: String,
    aggregate_version: Int,
    event_name: String,
    data: String,
  )
}

fn pgo_handler(
  db: pgo.Connection,
  event_encoder: fn(event) -> String,
  event_decoder: fn(String, String) -> event,
) {
  fn(msg: signal.StoreMessage(event), _state: Nil) {
    case msg {
      signal.StoreEvent(event) -> {
        let _ =
          event
          |> to_pgo_event(event_encoder)
          |> store_event(db)
        actor.continue(Nil)
      }
      signal.GetStoredEvents(s, aggregate_id) -> {
        case get_stored_events(db, aggregate_id) {
          pgo.Returned(count, rows) if count > 0 -> {
            let assert Ok(events) =
              result.all(
                list.map(rows, fn(row) { decode_event(row, event_decoder) }),
              )

            process.send(s, Ok(events))
            actor.continue(Nil)
          }
          _ -> {
            process.send(s, Error("Could not find events"))
            actor.continue(Nil)
          }
        }
      }
      signal.IsIdentityAvailable(s, identity) -> {
        case is_identity_available(db, identity) {
          pgo.Returned(count, _) if count > 0 -> {
            process.send(s, Ok(False))
            actor.continue(Nil)
          }
          _ -> {
            process.send(s, Ok(True))
            actor.continue(Nil)
          }
        }
      }
      signal.ShutdownPersistanceLayer -> {
        pgo.disconnect(db)
        actor.Stop(process.Normal)
      }
    }
  }
}

fn to_pgo_event(event: signal.Event(event), encode: fn(event) -> String) {
  PgoEvent(
    aggregate_id: event.aggregate_id,
    aggregate_version: event.aggregate_version,
    event_name: event.event_name,
    data: encode(event.data),
  )
}

fn decode_event(event: dynamic.Dynamic, decode: fn(String, String) -> event) {
  case
    dynamic.from(event)
    |> dynamic.decode4(
      PgoEvent,
      dynamic.element(0, dynamic.string),
      dynamic.element(1, dynamic.int),
      dynamic.element(2, dynamic.string),
      dynamic.element(3, dynamic.string),
    )
  {
    Ok(event) ->
      Ok(signal.Event(
        aggregate_id: event.aggregate_id,
        aggregate_version: event.aggregate_version,
        event_name: event.event_name,
        data: decode(event.event_name, event.data),
      ))
    Error(_) -> Error("Could not decode event")
  }
}

fn store_event(event: PgoEvent, db: pgo.Connection) {
  let assert Ok(_) =
    "INSERT INTO signal_event_store (aggregate_id, aggregate_version, event_name, data) VALUES ($1, $2, $3, $4)"
    |> pgo.execute(
      db,
      [
        pgo.text(event.aggregate_id),
        pgo.int(event.aggregate_version),
        pgo.text(event.event_name),
        pgo.text(event.data),
      ],
      dynamic.dynamic,
    )
}

fn get_stored_events(db: pgo.Connection, aggregate_id: String) {
  let assert Ok(rows) =
    "SELECT aggregate_id, aggregate_version, event_name, data FROM signal_event_store WHERE aggregate_id = $1"
    |> pgo.execute(db, [pgo.text(aggregate_id)], dynamic.dynamic)

  rows
}

fn is_identity_available(db: pgo.Connection, identity: String) {
  let assert Ok(rows) =
    "SELECT aggregate_id FROM signal_event_store WHERE aggregate_id = $1"
    |> pgo.execute(db, [pgo.text(identity)], dynamic.dynamic)

  rows
}
