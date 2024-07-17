import gleam/option.{type Option, None, Some}
import gleam/list.{append}

pub type ProductId =
  String

pub type Price {
  Price(Int, Currency)
}

pub type Currency {
  USD
  EUR
  GBP
}

pub type ProductCommands {
  CreateProduct(ProductId, Price)
  AddProductPicture(ProductId, String)
  AddProductDescritpion(ProductId, String)
  AddProductPrice(ProductId, Price)
  RestockProduct(ProductId, Int)
  PurchaseProduct(ProductId, Int)
}

pub type ProductEvents {
  ProductCreated(ProductId, Price)
  ProductPictureAdded(ProductId, String)
  ProductDescriptionAdded(ProductId, String)
  ProductPriceAdded(ProductId, Price)
  ProductRestocked(ProductId, Int)
  ProductPurchased(ProductId, Int)
  ProductOutOfStock(ProductId)
}

pub type Product {
  Product(
    id: ProductId,
    price: Price,
    stock: Int,
    pictures: List(String),
    description: Option(String),
  )
}

pub fn product_command_handler(
  state: Product,
  command: ProductCommands,
) -> Result(List(ProductEvents), String) {
  case command {
    CreateProduct(id, price) -> Ok([ProductCreated(id, price)])

    AddProductPicture(id, picture) -> Ok([ProductPictureAdded(id, picture)])

    AddProductDescritpion(id, description) ->
      Ok([ProductDescriptionAdded(id, description)])

    AddProductPrice(id, price) -> Ok([ProductPriceAdded(id, price)])

    RestockProduct(id, amount) -> Ok([ProductRestocked(id, amount)])

    PurchaseProduct(id, amount) if state.stock > amount ->
      Ok([ProductPurchased(id, amount)])

    PurchaseProduct(id, amount) if state.stock == amount ->
      Ok([ProductPurchased(id, amount), ProductOutOfStock(id)])

    PurchaseProduct(_, _) -> Error("Not enough stock")
  }
}

pub fn product_event_handler(state: Product, event: ProductEvents) -> Product {
  case event {
    ProductCreated(id, price) -> Product(id, price, 0, [], None)
    ProductPictureAdded(_, picture) ->
      Product(..state, pictures: append(state.pictures, [picture]))
    ProductDescriptionAdded(_, description) ->
      Product(..state, description: Some(description))
    ProductPriceAdded(_, price) -> Product(..state, price: price)
    ProductRestocked(_, amount) -> Product(..state, stock: state.stock + amount)
    ProductPurchased(_, amount) -> Product(..state, stock: state.stock - amount)
    _ -> state
  }
}
