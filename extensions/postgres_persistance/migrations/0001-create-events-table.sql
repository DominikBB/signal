CREATE TABLE IF NOT EXISTS signal_events (
    id SERIAL PRIMARY KEY,
    aggregate_id VARCHAR(255),
    aggregate_version INT,
    event_name VARCHAR(255),
    data JSON
);

CREATE INDEX IF NOT EXISTS idx_signal_events_aggregate_id ON signal_events (aggregate_id);