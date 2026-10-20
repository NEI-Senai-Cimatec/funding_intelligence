# scratch/test_db_concurrency.R
library(DBI)
library(RSQLite)

db_path <- "funding_intelligence.sqlite"
source("R/helpers_utils.R")
source("R/helpers_db.R")

message("Testing SQLite WAL Concurrency...")
conn1 <- get_db_connection(db_path)
conn2 <- get_db_connection(db_path)

on.exit({
  if (DBI::dbIsValid(conn1)) DBI::dbDisconnect(conn1)
  if (DBI::dbIsValid(conn2)) DBI::dbDisconnect(conn2)
})

# Test if WAL mode is active
journal_mode <- DBI::dbGetQuery(conn1, "PRAGMA journal_mode;")$journal_mode[[1]]
message(sprintf("Current journal mode: %s", journal_mode))

if (journal_mode != "wal") {
  stop("Error: WAL mode is not enabled!")
}

# Prepare table
DBI::dbExecute(conn1, "CREATE TABLE IF NOT EXISTS test_concurrency (id INTEGER PRIMARY KEY, val TEXT)")
DBI::dbExecute(conn1, "DELETE FROM test_concurrency")

# Start an uncommitted transaction in conn1 (simulating background writer)
DBI::dbBegin(conn1)
DBI::dbExecute(conn1, "INSERT INTO test_concurrency (id, val) VALUES (1, 'locked_value')")

# Try to read the table from conn2 (simulating UI reader thread)
res <- tryCatch({
  DBI::dbGetQuery(conn2, "SELECT * FROM test_concurrency")
}, error = function(e) e)

if (inherits(res, "error")) {
  message("FAIL: Reader was blocked or database locked during writer transaction.")
  message("Error details: ", res$message)
  DBI::dbRollback(conn1)
  stop("SQLite Concurrency test failed!")
} else {
  message("SUCCESS: Reader could read during transaction without blocking!")
  message(sprintf("Read returned %d rows (uncommitted transaction is isolated).", nrow(res)))
}

DBI::dbCommit(conn1)
message("Database concurrency test passed successfully!")
