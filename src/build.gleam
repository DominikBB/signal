import esgleam

pub fn main() {
  esgleam.new("./dist/static")
  |> esgleam.entry("gleames/aggregate.gleam")
  |> esgleam.kind(esgleam.Library)
  |> esgleam.platform(esgleam.Neutral)
  |> esgleam.bundle
}
