import app/web
import domain.{type Cart, type CartCommand, type CartEvent}
import gleam/string_builder
import wisp.{type Request, type Response}

/// We wrap the request handler with a higher order function to provide a
/// reference to emit
/// 
pub fn handle_request(
  emit: Emit(Cart, CartCommand, CartEvent),
  revenue_projection: emit.Consumer(CartEvent),
) {
  fn(req: Request) -> Response {
    use _req <- web.middleware(req)

    // TODO Get or create the cart

    // TODO Process the cart command

    case req.method, wisp.path_segments(req) {
      http.Get, [] -> page()
      http.Post, ["cart", id] -> todo
      _ -> wisp.not_found()
    }
  }
}

// Just HTML templates...

fn cart_items(item: product)

fn page() -> Response {
  let html =
    string_builder.from_string(
      "
      <!DOCTYPE html>
      <html lang='en'>
      <head>
        <meta charset='UTF-8'>
        <meta name='viewport' content='width=device-width, initial-scale=1.0'>
        <title>My Website</title>
        <link href='https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css' rel='stylesheet'>
        <script src='https://unpkg.com/htmx.org@^1.5.0'></script>
      </head>
      <body class='flex justify-center items-center h-screen'>
        <div class='grid grid-cols-2 gap-4'>
          <div>
            <ul class='space-y-4'>
              <li class='border p-4'>
                <div class='font-bold'>SKU: ABC123</div>
                <div>Price: $10</div>
                <div>Quantity: 5</div>
              </li>
              <li class='border p-4'>
                <div class='font-bold'>SKU: DEF456</div>
                <div>Price: $20</div>
                <div>Quantity: 3</div>
              </li>
            </ul>
            <form class='mt-4' hx-post='/add-item'>
              <div class='mb-4'>
                <label for='sku' class='block font-bold'>SKU:</label>
                <input type='text' id='sku' name='sku' class='border p-2 w-full' required>
              </div>
              <div class='mb-4'>
                <label for='price' class='block font-bold'>Price:</label>
                <input type='number' id='price' name='price' class='border p-2 w-full' required>
              </div>
              <div class='mb-4'>
                <label for='quantity' class='block font-bold'>Quantity:</label>
                <input type='number' id='quantity' name='quantity' class='border p-2 w-full' required>
              </div>
              <button type='submit' class='bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded'>Add Item</button>
            </form>
          </div>
          <div>
            <div class='mb-4'>
              <input type='text' class='border p-2 w-full unique-class-1' placeholder='Text Field 1'>
            </div>
            <div class='mb-4'>
              <input type='text' class='border p-2 w-full unique-class-2' placeholder='Text Field 2'>
            </div>
          </div>
        </div>
      </body>
      </html>
      ",
    )
  wisp.ok()
  |> wisp.html_body(html)
}
