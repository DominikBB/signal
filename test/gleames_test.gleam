import gleeunit
import gleeunit/should
import gleam/option.{type Option, None, Some}
import gleam/result.{map, try}
import gleam/io
import gleam/list.{append}
import gleames/handlers.{type CommandHandler}
import gleames/aggregate.{type Aggregate}
import test_model
import mock_handlers

pub fn main() {
  gleeunit.main()
}

pub fn can_generate_state_test() {
  todo
}

pub fn can_generate_projection_test() {
  todo
}

pub fn will_snapshot_state_test() {
  todo
}

pub fn will_snapshot_projection_test() {
  todo
}

pub fn can_handle_command_test() {
  let expected =
    test_model.Product(
      "1",
      test_model.Price(100, test_model.USD),
      0,
      ["picture"],
      Some("description"),
    )

  let commands = [
    test_model.CreateProduct(expected.id, test_model.Price(100, test_model.USD)),
    test_model.AddProductPicture(expected.id, "picture"),
    test_model.AddProductDescritpion(expected.id, "description"),
  ]

  let es = set_up_event_store()

  list.try_fold(commands, expected, fn(res, cmd) { es.handle(expected.id, cmd) })
  |> should.equal(Ok(expected))
}

fn set_up_event_store() {
  aggregate.create_aggregate(
    test_model.product_command_handler,
    test_model.product_event_handler,
    mock_handlers.mock_persistance([]),
    test_model.Product("", test_model.Price(0, test_model.USD), 0, [], None),
  )
}
