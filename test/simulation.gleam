import emit
import fixture
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option}
import gleam/set
import prng/random
import prng/seed
import youid/uuid

pub opaque type Simulation(command, event) {
  Simulation(
    sim_seed: Int,
    generator_seed: seed.Seed,
    list_of_aggregates: List(SimAggregate(command, event)),
  )
}

pub opaque type SimAggregate(command, event) {
  SimAggregate(
    id: String,
    events: List(#(Option(EventQuirks), emit.Event(event))),
    commands: List(#(Option(CommandQuirks), command)),
  )
}

/// Used only for tests that do not involve commands
pub type EventQuirks {
  IsLarge
  Duplicate
  DuplicateId
}

/// Used to determine which quirk, if any, should be attached to a particular command
pub type CommandQuirks {
  CreatesOneEvent
  CreatesDataHeavyEvent
  CreatesManyEvents
  CreatesNoEvents
  Errors
  Crashes
}

pub type TestWith {
  ManyAggregates
  SubscriberConsumers
  SubscriberPolicies
}

pub type Intensity {
  OneAggregate
  TenAggregates
  HoundredAggregates
  ThousandAggregates
  TenThousandAggregates
}

pub type TestWhat {
  TestEvents
  TestCommands
}

pub fn new(intensity: Intensity, test_what: TestWhat) {
  let sim_seed = uuid.v7() |> uuid.time_posix_microsec()
  io.print("Simulating with seed: " <> int.to_string(sim_seed))

  let generator_seed = seed.new(sim_seed)

  let sim =
    Simulation(
      sim_seed: sim_seed,
      generator_seed: generator_seed,
      list_of_aggregates: [],
    )
    |> create_aggregates_with_intensity(intensity, test_what)

  list.map(sim.list_of_aggregates, fn(agg) {
    generate_commands_or_events(agg, test_what, generator_seed)
  })
}

fn create_aggregates_with_intensity(
  sim: Simulation(fixture.DeliveryCommand, fixture.DeliveryEvent),
  intensity: Intensity,
  test_what: TestWhat,
) {
  case intensity {
    OneAggregate -> create_aggregates(sim, 1, test_what)
    TenAggregates -> create_aggregates(sim, 10, test_what)
    HoundredAggregates -> create_aggregates(sim, 100, test_what)
    ThousandAggregates -> create_aggregates(sim, 1000, test_what)
    TenThousandAggregates -> create_aggregates(sim, 10_000, test_what)
  }
}

fn generate_commands_or_events(
  sim: SimAggregate(fixture.DeliveryCommand, fixture.DeliveryEvent),
  test_what: TestWhat,
  seed: seed.Seed,
) {
  case test_what {
    TestCommands -> {
      let commands =
        sim
        |> generate_commands(seed)
        |> assign_data_to_commands(seed)
        |> add_quirks_to_commands([], seed, _)

      SimAggregate(..sim, commands: commands)
    }
    TestEvents -> sim
  }
}

fn assign_data_to_commands(
  sim: SimAggregate(fixture.DeliveryCommand, fixture.DeliveryEvent),
  seed: seed.Seed,
) {
  sim.commands
  |> list.map(fn(c) {
    generate_command_data(
      c,
      seed,
      generate_delivery_package_data([], seed, list.length(sim.commands) * 4),
    )
  })
}

fn generate_command_data(
  cmd: #(Option(CommandQuirks), fixture.DeliveryCommand),
  seed: seed.Seed,
  package_list: List(fixture.DeliveryPackage),
) {
  let #(quirk, command) = cmd
  let updated = case command {
    fixture.CreateRoute(_) as c -> c
    fixture.AssignPackages(_) -> fixture.AssignPackages(package_list)
    fixture.RemovePackage(_) -> {
      let assert Ok(first) = list.first(package_list)
      let pkg = random.uniform(first, package_list) |> random.sample(seed)
      fixture.RemovePackage(pkg.tracking_nr)
    }
    fixture.DeliverPackage(_) -> {
      let assert Ok(first) = list.first(package_list)
      let pkg = random.uniform(first, package_list) |> random.sample(seed)
      fixture.RemovePackage(pkg.tracking_nr)
    }
    c -> c
  }

  #(quirk, updated)
}

fn generate_delivery_package_data(
  pkgs: List(fixture.DeliveryPackage),
  seed: seed.Seed,
  package_quantity: Int,
) {
  let #(pkg_size, new_seed) = random.float(20.0, 90.0) |> random.step(seed)
  case package_quantity {
    0 -> pkgs
    n -> {
      let another =
        fixture.DeliveryPackage(
          tracking_nr: random.fixed_size_string(20) |> random.sample(seed),
          volume: #(pkg_size, pkg_size, pkg_size),
          note: random.fixed_size_string(50) |> random.sample(seed),
          status: fixture.Assigned,
        )

      generate_delivery_package_data([another, ..pkgs], new_seed, n - 1)
    }
  }
}

fn create_aggregates(
  sim: Simulation(fixture.DeliveryCommand, fixture.DeliveryEvent),
  number: Int,
  _test_what: TestWhat,
) {
  let ids =
    random.fixed_size_set(random.fixed_size_string(25), number)
    |> random.sample(sim.generator_seed)

  let aggregates =
    set.to_list(ids)
    |> list.filter(fn(id) { id != "" })
    |> list.map(fn(id) { SimAggregate(id: id, commands: [], events: []) })

  Simulation(..sim, list_of_aggregates: aggregates)
}

fn generate_commands(
  sim: SimAggregate(fixture.DeliveryCommand, fixture.DeliveryEvent),
  seed: seed.Seed,
) {
  SimAggregate(
    ..sim,
    commands: generate_command(
      [
        #(
          option.None,
          fixture.CreateRoute(random.string() |> random.sample(seed)),
        ),
      ],
      random.int(20, 200) |> random.sample(seed),
      seed,
    ),
  )
}

fn generate_command(
  generated_commands: List(#(Option(CommandQuirks), fixture.DeliveryCommand)),
  num_remaining: Int,
  seed: seed.Seed,
) {
  case num_remaining {
    0 -> generated_commands
    n ->
      case list.last(generated_commands) {
        Error(_) -> generated_commands
        Ok(#(_, cmd)) -> {
          let #(new_command, new_seed) =
            next_weighted_command(cmd) |> random.step(seed)

          [#(option.None, new_command), ..generated_commands]
          |> list.reverse()
          |> generate_command(n - 1, new_seed)
        }
      }
  }
}

fn add_quirks_to_commands(
  quirky_commands: List(#(Option(CommandQuirks), fixture.DeliveryCommand)),
  seed: seed.Seed,
  generated_commands: List(#(Option(CommandQuirks), fixture.DeliveryCommand)),
) {
  let #(_, new_seed) = random.int(1, 2) |> random.step(seed)
  case generate_commands {
    [] -> quirky_commands
    [next] -> [discover_quirk(next, seed), ..quirky_commands]
    [next, ..rest] ->
      add_quirks_to_commands(
        [discover_quirk(next, seed), ..quirky_commands],
        new_seed,
        rest,
      )
  }
}

fn discover_quirk(
  cmd: #(Option(CommandQuirks), fixture.DeliveryCommand),
  seed: seed.Seed,
) {
  let #(_, command) = cmd
  let quirk = case command {
    fixture.CreateRoute(_) -> option.None
    fixture.AssignPackages(_) ->
      random.weighted(#(0.8, option.None), [
        #(0.2 /. 3.0, option.Some(CreatesDataHeavyEvent)),
        #(0.2 /. 3.0, option.Some(CreatesManyEvents)),
        #(0.2 /. 3.0, option.Some(CreatesNoEvents)),
      ])
      |> random.sample(seed)
    fixture.RemovePackage(_)
    | fixture.DeliverPackage(_)
    | fixture.UnableToDeliverPackage(_) ->
      random.weighted(#(0.8, option.None), [#(0.2, option.Some(Errors))])
      |> random.sample(seed)
    fixture.CrazyCommand -> option.Some(Crashes)
  }

  let updated_command = case quirk, command {
    option.None, _ -> command
    option.Some(CreatesDataHeavyEvent), fixture.AssignPackages(pkgs) ->
      fixture.AssignPackages([
        fixture.DeliveryPackage(
          tracking_nr: random.fixed_size_string(2000) |> random.sample(seed),
          volume: #(
            random.float(20.0, 100.0) |> random.sample(seed),
            random.float(20.0, 100.0) |> random.sample(seed),
            random.float(20.0, 100.0) |> random.sample(seed),
          ),
          note: random.fixed_size_string(50) |> random.sample(seed),
          status: fixture.Assigned,
        ),
        ..pkgs
      ])

    option.Some(CreatesManyEvents), fixture.AssignPackages(pkgs) ->
      fixture.AssignPackages(list.append(
        generate_delivery_package_data([], seed, 200),
        pkgs,
      ))

    option.Some(CreatesNoEvents), fixture.AssignPackages(_) ->
      fixture.AssignPackages([])

    option.Some(Errors), fixture.RemovePackage(_) ->
      fixture.RemovePackage(random.fixed_size_string(20) |> random.sample(seed))

    option.Some(Errors), fixture.DeliverPackage(_) ->
      fixture.DeliverPackage(
        random.fixed_size_string(20) |> random.sample(seed),
      )

    option.Some(Errors), fixture.UnableToDeliverPackage(_) ->
      fixture.UnableToDeliverPackage(
        random.fixed_size_string(20) |> random.sample(seed),
      )

    _, _ -> command
  }

  #(quirk, updated_command)
}

// -----------------------------------------------------------------------------
//                                 Generators                                   
// -----------------------------------------------------------------------------

fn next_weighted_command(previous: fixture.DeliveryCommand) {
  case previous {
    fixture.CreateRoute(_) ->
      random.weighted(#(0.9, fixture.AssignPackages([])), [
        #(0.05, fixture.RemovePackage("")),
        #(0.05, fixture.DeliverPackage("")),
      ])
    fixture.AssignPackages(_) ->
      random.weighted(#(0.01, fixture.CrazyCommand), [
        #(0.79, fixture.RemovePackage("")),
        #(0.2, fixture.DeliverPackage("")),
      ])
    fixture.RemovePackage(_) ->
      random.weighted(#(0.01, fixture.CrazyCommand), [
        #(0.2, fixture.RemovePackage("")),
        #(0.79, fixture.DeliverPackage("")),
      ])
    fixture.DeliverPackage(_) ->
      random.weighted(#(0.01, fixture.CrazyCommand), [
        #(0.3, fixture.UnableToDeliverPackage("")),
        #(0.79, fixture.DeliverPackage("")),
      ])
    _ ->
      random.weighted(#(0.9, fixture.CrazyCommand), [
        #(0.5, fixture.UnableToDeliverPackage("")),
      ])
  }
}
