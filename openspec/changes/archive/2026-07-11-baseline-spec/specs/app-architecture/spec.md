## ADDED Requirements

### Requirement: Application bootstrap and package management
The system SHALL initialize by loading packages from a local `R_libs/` directory, auto-installing missing packages from CRAN, and refusing to start if any required package is unavailable. On Posit Connect (detected via `CONNECT_SERVER` or `CONNECT_API_KEY` env vars), auto-install is skipped.

#### Scenario: Successful local startup
- **WHEN** the application starts locally with all required packages installed
- **THEN** all 30 packages are loaded and the application serves on port 3838

#### Scenario: Missing package auto-install
- **WHEN** the application starts locally with packages missing from `R_libs/`
- **THEN** missing packages are installed from CRAN into `R_libs/` before loading

#### Scenario: Unrecoverable package failure
- **WHEN** a required package cannot be installed after attempt
- **THEN** the application stops with an error listing the missing packages

### Requirement: Helper module loading order
The system SHALL load helper modules in a fixed sequence via `safe_source()`: `helpers_utils.R` → `helpers_db.R` → `helpers_text.R` → `helpers_ai.R` → `helpers_recommend.R` → `helpers_collect.R` → `helpers_drive.R`. Each module load is wrapped in `try()` — a failed load emits a warning but does not prevent the app from starting.

#### Scenario: All modules load successfully
- **WHEN** all helper files exist and parse without error
- **THEN** all functions are available in the app scope

#### Scenario: Single module fails to load
- **WHEN** one helper file (e.g., `helpers_drive.R`) has a syntax error
- **THEN** a warning is emitted and the app continues with fallback behavior for that module

### Requirement: SQLite database initialization
The system SHALL initialize the SQLite database at `funding_intelligence.sqlite` by: (1) downloading from Google Drive if `GDRIVE_FILE_ID` is configured, (2) creating all 11 tables idempotently via `CREATE TABLE IF NOT EXISTS`, (3) seeding the source catalog with UPSERT, (4) seeding profile, saved searches, collaborators, demo opportunities, researchers, and projects, (5) running `cleanup_database_opportunities()` and `migrate_existing_keywords()`.

#### Scenario: Fresh database creation
- **WHEN** no `funding_intelligence.sqlite` exists and no Google Drive is configured
- **THEN** a new database is created with all 11 tables and seed data (including 2 demo opportunities)

#### Scenario: Existing database with Google Drive sync
- **WHEN** `GDRIVE_FILE_ID` is configured and a database exists on Google Drive
- **THEN** the local database is overwritten with the Drive version before initialization

### Requirement: Background collection process management
The system SHALL execute data collection in a separate R process via `callr::r_bg()`, passing all parameters explicitly as arguments. A global flag `.global_scraping_active` prevents concurrent collections. The parent process polls a JSON status file every 1.5 seconds. On session end, any active child process is killed via `session$onSessionEnded`.

#### Scenario: Single collection process
- **WHEN** user clicks "Atualizar base" and no collection is running
- **THEN** a child R process is launched and a progress modal is displayed

#### Scenario: Concurrent collection prevention
- **WHEN** user clicks "Atualizar base" while a collection is already running
- **THEN** a notification is shown and no new process is launched

#### Scenario: Session cleanup
- **WHEN** the browser session closes while a collection process is active
- **THEN** the child process is killed and `.global_scraping_active` is set to FALSE

### Requirement: Google Drive synchronization
The system SHALL synchronize the SQLite database with Google Drive using a Service Account. Download occurs on startup. Upload occurs after collection, after saving tracked opportunities or searches, and on app close (`onStop`). All operations are wrapped in `tryCatch` — failures produce notifications but do not block the application.

#### Scenario: Successful sync on startup
- **WHEN** `GDRIVE_FILE_ID` and Service Account credentials are configured
- **THEN** the database is downloaded from Google Drive before the app serves

#### Scenario: Upload after collection
- **WHEN** a background collection completes successfully
- **THEN** the updated database is uploaded to Google Drive

#### Scenario: Drive unavailable
- **WHEN** Google Drive credentials are missing or the service is unreachable
- **THEN** a warning notification is shown and the app uses the local database

### Requirement: UI structure with sidebar filters and multi-tab layout
The system SHALL present a `bslib::page_sidebar` UI with: a header containing the SENAI CIMATEC logo and dynamic status widget, a sidebar with 5 multi-select filters (Funder, Area, Status, Type, Language) plus a clear button, a search bar with boolean query input and region radio buttons, 4 value boxes, and 6 navigation tabs (Resultados, Por financiador, Buscas salvas, Editais rastreados, Recomendados para mim, Logs).

#### Scenario: Sidebar filter interaction
- **WHEN** user selects values in sidebar filters
- **THEN** the results table is filtered to match all selected criteria

#### Scenario: Clear filters
- **WHEN** user clicks "Limpar Filtros"
- **THEN** all sidebar filters are reset to empty and the full result set is shown

### Requirement: Dynamic progress modal for collection
The system SHALL display a modal dialog during collection with: a progress bar (animated, percentage-based), a phase badge (Scraping/IA/Concluído), a real-time log viewer (dark terminal-style), and minimize/close buttons. The modal reads from `collection_status.json` and `collection_modal_log.txt` via polling.

#### Scenario: Collection in progress
- **WHEN** a background collection is running
- **THEN** the progress modal shows current step, percentage, phase, and scrolling log output

#### Scenario: Collection completes
- **WHEN** the background process writes `status: "done"` to the status file
- **THEN** the progress bar reaches 100%, the phase badge shows "Concluído", and a "Concluir" button appears

#### Scenario: Collection fails
- **WHEN** the background process exits with an error
- **THEN** the progress bar turns red, the detail shows the error message, and a notification is displayed
