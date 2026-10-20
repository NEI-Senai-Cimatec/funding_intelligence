## 1. Export Utilities

- [x] 1.1 Create helpers_export.R file with export utility functions
- [x] 1.2 Implement export_to_xlsx() function using writexl package
- [x] 1.3 Implement export_to_csv() function using base R
- [x] 1.4 Add timestamped filename generation function

## 2. Data Preparation

- [x] 2.1 Update prepare_export_data() to include only 6 specific columns
- [x] 2.2 Include document and link columns in export data
- [x] 2.3 Remove formatted date and status columns (not needed)

## 3. Table Export UI

- [x] 3.1 Move download buttons to top left of table (near Show entries)
- [x] 3.2 Style download button with icon and tooltip
- [x] 3.3 Implement server-side handler for table export

## 4. Modal Export Integration

- [x] 4.1 Modify update database modal to show download options after collection
- [x] 4.2 Add XLSX and CSV download buttons in modal footer
- [x] 4.3 Implement server-side handlers for modal export

## 5. Testing and Validation

- [x] 5.1 Test XLSX export with only 6 specified columns
- [x] 5.2 Test CSV export with only 6 specified columns
- [x] 5.3 Test export from filtered results
- [x] 5.4 Test export after database collection
- [x] 5.5 Verify file naming convention
- [x] 5.6 Test UI responsiveness and button visibility at new position
