# download-ui

## ADDED Requirements

### Requirement: Download button at top left of results table
The system SHALL display download buttons at the top left of the results table, near the Show entries dropdown.

#### Scenario: Download button position
- **WHEN** the results table is displayed with data
- **THEN** download buttons are visible at the top left of the table, near the Show entries dropdown

### Requirement: Download button in update modal
The system SHALL display download buttons in the update database modal after collection completes.

#### Scenario: Download buttons in modal
- **WHEN** database collection completes successfully
- **THEN** the modal footer shows XLSX and CSV download buttons

### Requirement: Download button styling
The system SHALL style download buttons consistently with the existing UI.

#### Scenario: Button appearance
- **WHEN** download buttons are displayed
- **THEN** they follow the existing button styling patterns (colors, icons, spacing)

### Requirement: Download tooltip information
The system SHALL provide tooltips explaining the download functionality.

#### Scenario: Tooltip on hover
- **WHEN** user hovers over a download button
- **THEN** a tooltip appears explaining what will be downloaded
