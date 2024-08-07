import app/router
import domain.{type Cart, type InProgress}
import emit
import gleam/erlang/process
import mist
import wisp
import wisp/wisp_mist

pub fn main() {
  wisp.configure_logger()

  // This tells emit what state to use when a new cart is created (default state).
  // It also sets the comand and event handling function which are going to be used for
  // aggregate operations.
  //
  let aggregate_configuration =
    emit.AggregateConfig(
      initial_state: Cart(id: "", state: InProgress, products: set.new()),
      command_handler: domain.cart_command_handler(),
      event_handler: domain.cart_event_handler(),
    )

  // This gets our revenue report actor going
  //
  let assert Ok(revenue_report) =
    actor.start(domain.new_price(0), domain.revenue_projection)

  // This will configure and create our emit instance
  // You can handle errors in a nicer way, just keeping it simple.
  //
  let assert Ok(es_service) =
    emit.configure()
    |> emit.with_subscriber(revenue_report)
    |> emit.start()

  // We create a request router injected with emit
  //
  let cart_handler = router.handle_request(es_service, revenue_report)

  let assert Ok(_) =
    wisp_mist.handler(cart_handler, ".")
    |> mist.new
    |> mist.port(8000)
    |> mist.start_http

  process.sleep_forever()
}
