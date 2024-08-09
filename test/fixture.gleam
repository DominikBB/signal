import gleam/dict
import gleam/io
import gleam/list
import signal

// I want data that can:
// - Be used to run simulation tests with random inputs, easily
// - Be a relatively simple model
// - Include some form of list operations
// - Include a very data-heavy event
// - Include a CPU heavy calculation 
// - Include a Command that produces n number of events
// 

/// This is a really convoluted model used for testing the library, your real life models should not be designed this way!
/// In event sourcing, your goal is to keep the Aggregate focused on one thing, and Events small.
/// 
pub type DeliveryRoute {
  InProgressRoute(
    id: String,
    payload: List(DeliveryPackage),
    delivered_volume: Float,
    failed_volume: Float,
  )
}

pub type DeliveryPackage {
  DeliveryPackage(
    tracking_nr: String,
    volume: #(Float, Float, Float),
    note: String,
    status: PackageStatus,
  )
}

pub type PackageStatus {
  Assigned
  Delivered
  FailedDelivery
}

pub type DeliveryCommand {
  CreateRoute(id: String)
  AssignPackages(List(DeliveryPackage))
  RemovePackage(tracking_nr: String)
  DeliverPackage(tracking_nr: String)
  UnableToDeliverPackage(tracking_nr: String)
  CrazyCommand
}

pub type DeliveryEvent {
  RouteCreated(id: String)
  PackageAssigned(DeliveryPackage)
  PackageAssignmentFailed(tracking_nr: String)
  PackageRemoved(tracking_nr: String)
  PackageDelivered(tracking_nr: String)
  PackageDeliveryFailed(tracking_nr: String)
}

/// Command handler for the van route system, it defines business rules and behaviour
/// Creating a higher order function is a nice way to inject any dependencies
/// 
pub fn command_handler() -> signal.CommandHandler(
  DeliveryRoute,
  DeliveryCommand,
  DeliveryEvent,
) {
  fn(command: DeliveryCommand, state: DeliveryRoute) {
    case command {
      CreateRoute(id) -> {
        case state.id {
          "" -> Ok([RouteCreated(id)])
          _ -> Error("Route already created!")
        }
      }
      AssignPackages(pkgs) -> Ok(assign_packages_workflow([], pkgs))
      RemovePackage(tracking_nr) ->
        case take_package(state.payload, tracking_nr) {
          Ok(p) if p.status == Assigned -> Ok([PackageRemoved(tracking_nr)])
          Ok(p) -> Error("Its too late for that!")
          _ -> Error("Package not found!")
        }
      DeliverPackage(tracking_nr) ->
        case take_package(state.payload, tracking_nr) {
          Ok(p) if p.status == Assigned -> Ok([PackageDelivered(tracking_nr)])
          Ok(p) -> Error("Its too late for that!")
          _ -> Error("Package not found!")
        }
      UnableToDeliverPackage(tracking_nr) ->
        case take_package(state.payload, tracking_nr) {
          Ok(p) if p.status == Assigned ->
            Ok([PackageDeliveryFailed(tracking_nr)])
          Ok(p) -> Error("Its too late for that!")
          _ -> Error("Package not found!")
        }
      CrazyCommand -> {
        panic as "Exploded"
      }
    }
  }
}

fn take_package(pkgs: List(DeliveryPackage), tracking_nr: String) {
  list.find(pkgs, fn(p) { p.tracking_nr == tracking_nr })
}

fn assign_packages_workflow(
  events: List(DeliveryEvent),
  pkgs: List(DeliveryPackage),
) {
  case pkgs {
    [] -> events
    [n] if n.status == Assigned -> [PackageAssigned(n), ..events]
    [n] -> [PackageAssignmentFailed(n.tracking_nr)]
    [n, ..rest] if n.status == Assigned ->
      [PackageAssigned(n), ..events] |> assign_packages_workflow(rest)
    [n, ..rest] ->
      [PackageAssignmentFailed(n.tracking_nr), ..events]
      |> assign_packages_workflow(rest)
  }
}

pub fn event_handler() -> signal.EventHandler(DeliveryRoute, DeliveryEvent) {
  fn(state: DeliveryRoute, event: signal.Event(DeliveryEvent)) {
    case event.data {
      RouteCreated(id) -> InProgressRoute(..state, id: id)
      PackageAssigned(pkg) ->
        InProgressRoute(..state, payload: [pkg, ..state.payload])
      PackageAssignmentFailed(tracking_nr) -> state
      PackageRemoved(tracking_nr) ->
        InProgressRoute(
          ..state,
          payload: list.filter(state.payload, fn(p) {
            p.tracking_nr == tracking_nr
          }),
        )
      PackageDelivered(tracking_nr) ->
        handle_package_delivery_update(state, tracking_nr, Delivered)
      PackageDeliveryFailed(tracking_nr) ->
        handle_package_delivery_update(state, tracking_nr, FailedDelivery)
    }
  }
}

fn handle_package_delivery_update(
  state: DeliveryRoute,
  tracking_nr: String,
  to: PackageStatus,
) {
  let new_list =
    list.map(state.payload, fn(p) {
      case p {
        pkg if pkg.tracking_nr == tracking_nr ->
          DeliveryPackage(..pkg, status: to)
        pkg -> pkg
      }
    })
  let #(delivered_volume, failed_volume) = calculate_total_volumes(new_list)

  InProgressRoute(
    ..state,
    payload: new_list,
    delivered_volume: delivered_volume,
    failed_volume: failed_volume,
  )
}

/// Intentionally un-optimized function for testing
/// 
fn calculate_total_volumes(pkgs: List(DeliveryPackage)) {
  list.fold(pkgs, #(0.0, 0.0), fn(agg, p) {
    let #(w, l, h) = p.volume
    let #(del, fail) = agg
    case p.status {
      Delivered -> #(del +. { w *. l *. h }, fail)
      FailedDelivery -> #(del, fail +. { w *. l *. h })
      _ -> agg
    }
  })
}
