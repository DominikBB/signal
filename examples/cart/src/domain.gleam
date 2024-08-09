import signal
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/set

// This is all of the business logic of the cart application

// ---------------------------- The domain model -------------------------------

pub type Cart {
  Cart(state: CartState, products: set.Set(Product))
}

pub type CartState {
  InProgress
  Paid
}

pub type Product {
  Product(sku: Sku, qty: Quantity, price: Price)
}

pub type Sku =
  String

pub type Quantity =
  Int

pub opaque type Price {
  Price(Int)
}

/// Represents operations that can be performed on the cart
/// 
pub type CartCommand {
  AddToCart(Product)
  RemoveFromCart(Sku)
  CompletePurchase
}

/// Represents the resulting state changes from running commands
/// Note - they are in the past tense
/// 
pub type CartEvent {
  ProductAdded(Product)
  ProductRemoved(Product)
  CartPaid(Price)
}

// -------------------------- The domain behaviour -----------------------------

/// A higher order function allows for injecting dependencies, 
/// and adds guidance to ensure your function complies with the emits CommandHandler type
/// 
pub fn cart_command_handler() -> signal.CommandHandler(
  Cart,
  CartCommand,
  CartEvent,
) {
  fn(message: CartCommand, cart: Cart) {
    case message {
      AddToCart(product) -> {
        case
          cart.state,
          set.to_list(cart.products)
          |> list.filter(fn(p) { p.sku == product.sku })
        {
          InProgress, [p] -> Error("Product already in cart!")
          InProgress, [] -> Ok([ProductAdded(product)])
          Paid, _ -> Error("Cannot add to a paid cart!")
          _, _ -> Error("More then one unique product should not exist!")
        }
      }
      RemoveFromCart(sku) -> {
        let product_from_cart =
          cart.products
          |> set.to_list()
          |> list.filter(fn(p) { p.sku == sku })

        case cart.state, product_from_cart {
          InProgress, [p] -> Ok([ProductRemoved(p)])
          Paid, _ -> Error("Cannot remove from a paid cart!")
          _, [] ->
            Error("The product you are trying to remove is not in the cart!")
          _, _ -> Error("More then one unique product should not exist!")
        }
      }
      CompletePurchase ->
        case cart.state {
          InProgress -> {
            let total_price =
              cart.products
              |> set.to_list()
              |> list.fold(zero_price(), fn(total, product) {
                add_prices(total, product.price)
              })

            Ok([CartPaid(total_price)])
          }
          _ -> Error("Cannot pay for an alrady paid cart!")
        }
    }
  }
}

// --------------------------- The state mutation ------------------------------

/// Notice that the event handler accepts an signal.Event, which adds some
/// metadata to your events, and lets you use them, such as aggregate version.
/// 
pub fn cart_event_handler() -> signal.EventHandler(Cart, CartEvent) {
  fn(cart: Cart, event: signal.Event(CartEvent)) {
    case event.data {
      ProductAdded(product) ->
        Cart(..cart, products: set.insert(cart.products, product))
      ProductRemoved(product) ->
        Cart(
          ..cart,
          products: cart.products
            |> set.delete(product),
        )
      CartPaid(_) -> Cart(..cart, state: Paid)
    }
  }
}

// -------------------------- Reporting projection -----------------------------
// Lets figure out how much revenue we made with our carts

/// This will be an OTP actor that listens to cart events
pub fn revenue_report_handler(
  message: signal.ConsumerMessage(Price, CartEvent),
  revenue: Price,
) {
  case message {
    // Revenue report only cares about the CartPaid event
    signal.Consume(signal.Event(_, _, _, data: CartPaid(purchase_price))) ->
      actor.continue(add_prices(revenue, purchase_price))
    signal.GetConsumerState(s) -> {
      process.send(s, revenue)
      actor.continue(revenue)
    }
    signal.ShutdownConsumer -> actor.Stop(process.Normal)
    _ -> actor.continue(revenue)
  }
}

// ---------------------------- Helper functions -------------------------------

pub fn new_price(price: Int) {
  case price {
    p if p >= 0 -> Ok(Price(price))
    _ -> Error("Price has to be positive")
  }
}

pub fn add_prices(p1p: Price, p2p: Price) {
  let Price(p1) = p1p
  let Price(p2) = p2p
  Price(p1 + p2)
}

pub fn zero_price() {
  Price(0)
}

pub fn price_to_string(price: Price) {
  let Price(int_price) = price
  int.to_string(int_price)
}
