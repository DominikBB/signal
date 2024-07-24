pub type Event(event) {
  Event(
    aggregate_version: Int,
    aggregate_id: String,
    event_name: String,
    data: event,
  )
}
// TODO Mby add a signature to the list of fields, and perhaps an event name
