import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/otp/task
import gleam/result

const max_timeout = 100

pub type BusMessage(data) {
  Message(s: process.Subject(Result(Nil, Nil)), data)
  Subscribe(
    friendly_name: String,
    consistent: Bool,
    manage_lifecycle: Bool,
    subscriber: process.Subject(SubscriberMessage(data)),
  )
  UnSubscribe(friendly_name: String)
  Shutdown
}

pub type Subscriber(data) {
  Subscriber(process.Subject(SubscriberMessage(data)))
}

pub type SubscriberMessage(data) {
  Consume(process.Subject(Result(Nil, Nil)), data)
  ShutdownSubscriber
}

pub fn add_policy(
  bus: process.Subject(BusMessage(data)),
  friendly_name: String,
  with_acknoledgement: Bool,
  policy: fn(data) -> fn() -> Result(Nil, Nil),
) {
  use policy_exec <- result.map(actor.start(Nil, policy_executor(policy)))

  add_consumer(bus, friendly_name, with_acknoledgement, True, policy_exec)
}

pub fn remove_subscriber(
  bus: process.Subject(BusMessage(data)),
  friendly_name: String,
) {
  actor.send(bus, UnSubscribe(friendly_name))
}

pub fn add_consumer(
  bus: process.Subject(BusMessage(data)),
  friendly_name: String,
  with_acknoledgement: Bool,
  with_managed_lifecycle: Bool,
  consumer: process.Subject(SubscriberMessage(data)),
) {
  actor.send(
    bus,
    Subscribe(
      friendly_name,
      with_acknoledgement,
      with_managed_lifecycle,
      consumer,
    ),
  )
}

pub fn bus_handler(
  received: BusMessage(data),
  subscribers: #(
    List(#(String, process.Subject(SubscriberMessage(data)))),
    List(#(String, process.Subject(SubscriberMessage(data)))),
    List(#(String, process.Subject(SubscriberMessage(data)))),
  ),
) {
  case received {
    Message(s, data) -> {
      let #(consistent, other, _) = subscribers
      case fan_out(data, consistent) {
        Ok(_) -> actor.send(s, Ok(Nil))
        Error(_) -> actor.send(s, Error(Nil))
      }

      list.map(other, fn(sub) {
        let #(_, s) = sub
        process.try_call(s, Consume(_, data), max_timeout)
      })

      actor.continue(subscribers)
    }
    Subscribe(friendly_name, consistant, manage_lifecycle, sub) -> {
      let #(consistent, other, managed) = subscribers
      let updated_managed_subscribers = case manage_lifecycle {
        True -> [#(friendly_name, sub), ..managed]
        False -> managed
      }

      let #(updated_consistent, updated_other) = case consistant {
        // Order matters for consistent subs
        True -> #(
          [#(friendly_name, sub), ..list.reverse(consistent)] |> list.reverse(),
          other,
        )
        False -> #(consistent, [#(friendly_name, sub), ..other])
      }

      actor.continue(#(
        updated_consistent,
        updated_other,
        updated_managed_subscribers,
      ))
    }
    UnSubscribe(friendly_name) -> {
      let #(consistent, other, managed) = subscribers
      let #(to_kill, rest) =
        list.partition(managed, fn(sub) {
          let #(name, _) = sub
          name == friendly_name
        })
      list.map(to_kill, fn(sub) {
        let #(_, s) = sub
        actor.send(s, ShutdownSubscriber)
      })

      actor.continue(#(
        list.filter(consistent, fn(sub) {
          let #(name, _) = sub
          name != friendly_name
        }),
        list.filter(other, fn(sub) {
          let #(name, _) = sub
          name != friendly_name
        }),
        rest,
      ))
    }
    Shutdown -> {
      let #(_, _, managed) = subscribers
      list.map(managed, fn(sub) {
        let #(_, s) = sub
        actor.send(s, ShutdownSubscriber)
      })
      actor.Stop(process.Normal)
    }
  }
}

fn fan_out(
  message: data,
  subscribers: List(#(String, process.Subject(SubscriberMessage(data)))),
) {
  result.all(
    list.map(subscribers, fn(sub) {
      let #(_, s) = sub
      process.try_call(s, Consume(_, message), max_timeout)
    }),
  )
}

/// Helper that acknolwedges a that a message is received and continues the actor after a callback is done processing the message.
/// 
pub fn ack(s: process.Subject(Result(Nil, Nil)), callback: fn() -> state) {
  process.send(s, Ok(Nil))
  callback()
  |> actor.continue()
}

pub fn policy_executor(policy: fn(data) -> fn() -> Result(Nil, Nil)) {
  fn(msg: SubscriberMessage(data), _state: Nil) {
    case msg {
      Consume(s, d) -> {
        use <- ack(s)
        let task = task.async(policy(d))
        let _ = task.await(task, max_timeout)
        Nil
      }
      ShutdownSubscriber -> {
        actor.Stop(process.Normal)
      }
    }
  }
}
