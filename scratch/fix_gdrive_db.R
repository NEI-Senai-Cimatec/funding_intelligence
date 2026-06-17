source("R/helpers_utils.R")
source("R/helpers_db.R")
source("R/helpers_drive.R")

db_path <- "funding_intelligence.sqlite"

# Delete any existing local sqlite / journal files to avoid contamination
if (file.exists(db_path)) {
  file.remove(db_path)
}
if (file.exists(paste0(db_path, "-wal"))) {
  file.remove(paste0(db_path, "-wal"))
}
if (file.exists(paste0(db_path, "-shm"))) {
  file.remove(paste0(db_path, "-shm"))
}

message("Initializing clean database locally...")
init_database(db_path)

message("Verifying local database integrity...")
conn <- get_db_connection(db_path)
integrity <- DBI::dbGetQuery(conn, "PRAGMA integrity_check;")
print(integrity)
DBI::dbDisconnect(conn)

message("Uploading clean database to Google Drive to replace the malformed one...")
res <- drive_upload_db(db_path)
if (res) {
  message("SUCCESS: Clean database uploaded to GDrive!")
} else {
  message("FAIL: Could not upload database to GDrive.")
}
