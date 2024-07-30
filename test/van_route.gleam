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
pub type VanRoute {
  Route(payload: List(DeliveryPackage))
  RouteWithVan(
    registration: String,
    lot: String,
    payload: List(DeliveryPackage),
  )
  RouteInProgress(registration: String, payload: List(DeliveryPackage))
  RouteComplete
}

pub type DeliveryPackage {
  Undelivered(
    recipient: String,
    destination_coords: #(Float, Float),
    weight: Int,
    note: String,
  )
  Delivered(at: String)
}

pub type Commands {
  AssignRoute(payload: List(DeliveryPackage))
  AssignVehicleAndWarehouse(registration: String, lot: String)
  LoadPackage(DeliveryPackage)
  StartRoute
  DeliverPackage(DeliveryPackage)
  FailDelivery(DeliveryPackage)
}

pub type Events {
  RouteAssigned(payload: List(DeliveryPackage))
  VehicleAndWarehouseAssigned(registration: String, lot: String)
  PackageLoaded(DeliveryPackage)
  RouteStarted
  PackageDelivered(DeliveryPackage)
  PackageDeliveryFailed(DeliveryPackage)
  RouteCompleted(packages_returned: String)
  PackageWillBeDeliveredTo(warehouse: String)
}
