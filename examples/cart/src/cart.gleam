import app/router
import domain
import gleam/erlang/process
import gleam/otp/actor
import gleam/set
import mist
import signal
import wisp

pub fn main() {
  wisp.configure_logger()

  // This tells signal what state to use when a new cart is created (default state).
  // It also sets the comand and event handling function which are going to be used for
  // aggregate operations.
  //
  let aggregate_configuration =
    signal.AggregateConfig(
      initial_state: domain.Cart(state: domain.InProgress, products: set.new()),
      command_handler: domain.cart_command_handler(),
      event_handler: domain.cart_event_handler(),
    )

  // This gets our revenue report actor going
  //
  let assert Ok(revenue_report) =
    actor.start(domain.zero_price(), domain.revenue_report_handler)

  // This will configure and create our signal instance
  // You can handle errors in a nicer way, just keeping it simple.
  //
  let assert Ok(es_service) =
    signal.configure(aggregate_configuration)
    |> signal.with_subscriber(signal.Consumer(revenue_report))
    |> signal.start()

  // We create a request router injected with signal
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
