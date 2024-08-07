// This is esentially all of the business logic of the cart application

// ---------------------------- The domain model -------------------------------

pub type Cart {
  Cart(id: String, state: CartState, products: set.Set(Product))
}

pub type CartState {
  InProgress
  Paid
}

pub type Product {
  Product(Sku, Quantity, Price)
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
/// Note - you dont need to create a higher order function, but it makes for better
/// DevEx and extensibility 
/// 
pub fn cart_command_handler() -> emit.CommandHandler(
  Cart,
  CartCommand,
  CartEvent,
) {
  fn(message: CartCommand, cart: Cart) {
    case message {
      AddToCart(product) -> Ok([ProductAdded(product)])
      RemoveFromCart(sku) -> {
        let product_from_cart =
          cart.products
          |> set.to_list()
          |> list.filter(fn(p) { p.sku == sku })

        case product_from_cart {
          [p] -> Ok([ProductRemoved(p)])
          [] ->
            Error("The product you are trying to remove is not in the cart!")
          _ -> Error("More then one unique product should not exist!")
        }
      }
      CompletePurchase ->
        case cart.state {
          InProgress -> {
            let total_price =
              cart.products
              |> set.to_list()
              |> list.reduce(fn(total, product) {
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

/// Notice that the event handler accepts an emit.Event, which adds some
/// metadata to your events, and lets you use them, such as aggregate version.
/// 
pub fn cart_event_handler() -> emit.EventHandler(Cart, CartEvent) {
  fn(event: emit.Event(CartEvent), cart: Cart) {
    case message {
      ProductAdded(product) -> Cart(..cart, products: set.insert(cart, product))
      ProductRemoved(sku) ->
        Cart(
          ..cart,
          products: cart.products
            |> set.to_list()
            |> list.filter(fn(p) { p.sku == sku })
            |> set.from_list(),
        )
    }
  }
}

// -------------------------- Reporting projection -----------------------------
// Lets figure out how much revenue we made with our carts

/// This will be an OTP actor that listens to cart events
pub fn revenue_report_handler(
  message: emit.ConsumerMessage(CartEvent),
  revenue: Price,
) {
  case message {
    // Revenue report only cares about the CartPaid event
    CartPaid(purchase_price) ->
      actor.continue(add_prices(revenue, purchase_price))
    _ -> actor.continue(revenue)
  }
}

// -------------------------- Price helper function ----------------------------

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
