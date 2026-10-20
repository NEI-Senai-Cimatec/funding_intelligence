# data-export

## ADDED Requirements

### Requirement: Export filtered results to XLSX
The system SHALL allow users to export the currently filtered results table to an XLSX file with specific columns only.

#### Scenario: Export filtered data to XLSX
- **WHEN** user clicks the XLSX download button
- **THEN** the system generates an XLSX file containing only these columns: Titulo, Entidade, Prazo Limite, Link Portal, Link Detalhes, Link PDF

### Requirement: Export filtered results to CSV
The system SHALL allow users to export the currently filtered results table to a CSV file with specific columns only.

#### Scenario: Export filtered data to CSV
- **WHEN** user clicks the CSV download button
- **THEN** the system generates a CSV file containing only these columns: Titulo, Entidade, Prazo Limite, Link Portal, Link Detalhes, Link PDF

### Requirement: Export includes only specified columns
The export SHALL include only the following columns: Titulo, Entidade, Prazo Limite, Link Portal, Link Detalhes, and Link PDF.

#### Scenario: Export contains exactly 6 columns
- **WHEN** user exports data to XLSX or CSV
- **THEN** the export contains exactly 6 columns with the specified names and data

### Requirement: Export after database update
The system SHALL provide export options in the update database modal after collection completes.

#### Scenario: Download option after collection
- **WHEN** database collection completes successfully
- **THEN** the modal displays download buttons for XLSX and CSV formats

### Requirement: Export file naming convention
The system SHALL generate export files with timestamped filenames.

#### Scenario: Timestamped filename
- **WHEN** user exports data
- **THEN** the filename follows the pattern quiiin_export_YYYYMMDD_HHMMSS.xlsx/csv
