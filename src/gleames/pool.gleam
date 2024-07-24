import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleames/aggregate.{type Aggregate}

pub type Pool(aggregate) =
  AggregatePool(Subject(AggregatePoolMessage(aggregate)))

pub type PoolMessage(aggregate) {
  Create(reply_with: Subject(Result(Aggregate(aggregate), String)), id: String)
  Get(reply_with: Subject(Aggregate(aggregate)), id: String)
  GetOrCreate(reply_with: Subject(Aggregate(aggregate)), id: String)
  Shutdown
}

pub fn handle_aggregate_pool_operations(
  operation: AggregatePoolMessage(aggregate),
  pool: List(Aggregate(aggregate)),
) {
  case operation {
    Create(client, with_id) -> {
      process.send(client, Error("Not Implemented"))
      actor.continue(pool)
    }
    Get(client, id) -> {
      todo
    }
    GetOrCreate(client, id) -> {
      todo
    }
    Shutdown -> actor.Stop(process.Normal)
  }
}
