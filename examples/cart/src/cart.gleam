import app/router
import domain
import emit
import gleam/erlang/process
import gleam/otp/actor
import gleam/set
import mist
import wisp

pub fn main() {
  wisp.configure_logger()

  // This tells emit what state to use when a new cart is created (default state).
  // It also sets the comand and event handling function which are going to be used for
  // aggregate operations.
  //
  let aggregate_configuration =
    emit.AggregateConfig(
      initial_state: domain.Cart(state: domain.InProgress, products: set.new()),
      command_handler: domain.cart_command_handler(),
      event_handler: domain.cart_event_handler(),
    )

  // This gets our revenue report actor going
  //
  let assert Ok(revenue_report) =
    actor.start(domain.zero_price(), domain.revenue_report_handler)

  // This will configure and create our emit instance
  // You can handle errors in a nicer way, just keeping it simple.
  //
  let assert Ok(es_service) =
    emit.configure(aggregate_configuration)
    |> emit.with_subscriber(emit.Consumer(revenue_report))
    |> emit.start()

  // We create a request router injected with emit
  //
  let cart_handler = router.handle_request(es_service, revenue_report)

  let assert Ok(_) =
    cart_handler
    |> wisp.mist_handler("")
    |> mist.new
    |> mist.port(8000)
    |> mist.start_http

  process.sleep_forever()
}
