import emit
import gleam/int
import gleam/io
import prng/random
import prng/seed
import van_route.{type DeliveryCommand, type DeliveryEvent}
import youid/uuid

pub opaque type Simulation(command, event) {
  Simulation(sim_seed: Int, list_of_aggregates: List(SimState(command, event)))
}

pub opaque type SimState(command, event) {
  SimState(
    id: String,
    events: List(#(SimEventType, emit.Event(event))),
    commands: List(#(CommandThat, command)),
  )
}

pub type SimEventType {
  Duplicate
  DuplicateId
}

pub type CommandThat {
  CreatesOneEvent
  CreatesDataHeavyEvent
  CreatesManyEvents
  CreatesNoEvents
  Errors
  Crashes
}

pub fn new() {
  let sim_seed = uuid.v7() |> uuid.time_posix_microsec()
  io.print("Simulating with seed: " <> int.to_string(sim_seed))

  let generator = seed.new(sim_seed)

  Simulation(sim_seed: sim_seed, list_of_aggregates: [])
}

pub fn process(sim: Simulation(DeliveryCommand, DeliveryEvent)) {
  todo
}

// --------------------------- Aggregate fixtures ------------------------------

pub fn with_aggregates(
  sim: Simulation(DeliveryCommand, DeliveryEvent),
  quantity: Int,
) {
  todo
}

pub fn with_aggregates_many(sim: Simulation(DeliveryCommand, DeliveryEvent)) {
  todo
}

// ---------------------------- Command fixtures -------------------------------

pub fn with_command_that_results_in_many_events(
  sim: Simulation(DeliveryCommand, DeliveryEvent),
) {
  todo
}

pub fn with_command_that_results_in_error(
  sim: Simulation(DeliveryCommand, DeliveryEvent),
) {
  todo
}

pub fn with_command_that_panics(sim: Simulation(DeliveryCommand, DeliveryEvent)) {
  todo
}

// ----------------------------- Event fixtures --------------------------------

pub fn with_event_that_is_a_duplicate(
  sim: Simulation(DeliveryCommand, DeliveryEvent),
) {
  todo
}

pub fn with_event_that_has_a_duplicate_aggregate_version(
  sim: Simulation(DeliveryCommand, DeliveryEvent),
) {
  todo
}

// ------------------------------ Pool fixtures --------------------------------

pub fn with_pool_of_aggregates(
  sim: Simulation(DeliveryCommand, DeliveryEvent),
  num_of_aggregates: Int,
) {
  todo
}

// --------------------------- Subscriber fixtures -----------------------------

pub fn with_subscriber_consumers(
  sim: Simulation(DeliveryCommand, DeliveryEvent),
  num_of_consumers: Int,
) {
  todo
}

pub fn with_subscriber_policies(
  sim: Simulation(DeliveryCommand, DeliveryEvent),
  num_of_policies: Int,
) {
  todo
}

pub fn with_subscriber_mix(
  sim: Simulation(DeliveryCommand, DeliveryEvent),
  num_of_subscribers: Int,
) {
  todo
}
