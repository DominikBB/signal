SELECT *
FROM signal_events
WHERE aggregate_id = $1
LIMIT 1;