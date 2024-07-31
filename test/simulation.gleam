import emit
import fixture
import gleam/int
import gleam/io
import gleam/list
import gleam/set
import prng/random
import prng/seed
import van_route.{type DeliveryCommand, type DeliveryEvent}
import youid/uuid

pub opaque type Simulation(command, event) {
  Simulation(
    sim_seed: Int,
    generator_seed: seed.Seed,
    test_with: set.Set(TestWith),
    list_of_aggregates: List(SimState(command, event)),
  )
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

pub type TestWith {
  ManyAggregates

  DuplicatedEvent
  EventWithDuplicateId
  EventVersionsMissing

  CommandThatCreatesOneEvent
  CommandThatCreatesDataHeavyEvent
  CommandThatCreatesManyEvents
  CommandThatCreatesNoEvents
  CommandThatErrors
  CommandThatCrashes

  SubscriberConsumers
  SubscriberPolicies
}

pub type Intensity {
  TenAggregates
  HoundredAggregates
  ThousandAggregates
  TenThousandAggregates
}

pub type TestWhat {
  Events
  Commands
  EventsAndCommands
}

pub fn new(test_with_random: Int) {
  let sim_seed = uuid.v7() |> uuid.time_posix_microsec()
  io.print("Simulating with seed: " <> int.to_string(sim_seed))

  let generator_seed = seed.new(sim_seed)

  case test_with_random {
    0 ->
      Simulation(
        sim_seed: sim_seed,
        generator_seed: generator_seed,
        test_with: set.new(),
        list_of_aggregates: [],
      )
    n -> {
      let #(picked_test_withs, updated_seed) =
        test_with_generator(n) |> random.step(generator_seed)

      Simulation(
        sim_seed: sim_seed,
        generator_seed: generator_seed,
        test_with: picked_test_withs,
        list_of_aggregates: [],
      )
    }
  }
}

pub fn build(
  sim: Simulation(DeliveryCommand, DeliveryEvent),
  intensity: Intensity,
  test_what: TestWhat,
) {
  case intensity {
    TenAggregates -> create_aggregates(sim, 10, test_what)
    HoundredAggregates -> create_aggregates(sim, 100, test_what)
    ThousandAggregates -> create_aggregates(sim, 1000, test_what)
    TenThousandAggregates -> create_aggregates(sim, 10_000, test_what)
  }
}

fn create_aggregates(
  sim: Simulation(DeliveryCommand, DeliveryEvent),
  number: Int,
  test_what: TestWhat,
) {
  let #(ids, _) =
    random.fixed_size_set(random.fixed_size_string(25), number)
    |> random.step(sim.generator_seed)

  let aggregates =
    set.to_list(ids)
    |> list.filter(fn(id) { id == "" })
    |> list.map(fn(id) {
      SimState(
        id: id,
        commands: case test_what {
          Commands | EventsAndCommands -> command_generator(sim)
          _ -> []
        },
        events: case test_what {
          Commands | EventsAndCommands -> event_generator(sim)
          _ -> []
        },
      )
    })

  Simulation(..sim, list_of_aggregates: aggregates)
}

// -----------------------------------------------------------------------------
//                                 Generators                                   
// -----------------------------------------------------------------------------

fn test_with_generator(size: Int) {
  random.fixed_size_set(
    random.uniform(ManyAggregates, [
      DuplicatedEvent,
      EventWithDuplicateId,
      EventVersionsMissing,
      CommandThatCreatesOneEvent,
      CommandThatCreatesDataHeavyEvent,
      CommandThatCreatesManyEvents,
      CommandThatCreatesNoEvents,
      CommandThatErrors,
      CommandThatCrashes,
      SubscriberConsumers,
      SubscriberPolicies,
    ]),
    size,
  )
}

fn command_generator(sim: Simulation(DeliveryCommand, DeliveryEvent)) {
  todo
}

fn event_generator(sim: Simulation(DeliveryCommand, DeliveryEvent)) {
  todo
}

fn next_weighted_command(previous: fixture.DeliveryCommand) {
  case previous {
    fixture.CreateRoute(_) ->
      random.weighted(#(0.9, fixture.AssignPackages), [
        #(0.05, fixture.RemovePackage),
        #(0.05, fixture.DeliverPackage),
      ])
    fixture.AssignPackages(_) ->
      random.weighted(#(0.01, fixture.CrazyCommand), [
        #(0.79, fixture.RemovePackage),
        #(0.2, fixture.DeliverPackage),
      ])
    fixture.RemovePackage(_) ->
      random.weighted(#(0.01, fixture.CrazyCommand), [
        #(0.2, fixture.RemovePackage),
        #(0.79, fixture.DeliverPackage),
      ])
    fixture.DeliverPackage(_) ->
      random.weighted(#(0.01, fixture.CrazyCommand), [
        #(0.3, fixture.UnableToDeliverPackage),
        #(0.79, fixture.DeliverPackage),
      ])
    _ -> random.weighted(#(0.9, CrazyCommand), [#(0.5, UnableToDeliverPackage)])
  }
}

// pub type SimEventType {
//   Duplicate
//   DuplicateId
// }

// pub type CommandThat {
//   CreatesOneEvent
//   CreatesDataHeavyEvent
//   CreatesManyEvents
//   CreatesNoEvents
//   Errors
//   Crashes
// }

pub fn generate_commmand(that: CommandThat) {
  case that {
    CreatesOneEvent -> todo
    CreatesDataHeavyEvent -> todo
    CreatesManyEvents -> todo
    CreatesNoEvents -> todo
    Errors -> todo
    Crashes -> todo
  }
}
