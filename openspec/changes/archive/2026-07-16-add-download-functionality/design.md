## Context

The QuIIN platform is a Shiny-based application that collects and displays funding opportunities from various sources. Currently, the application displays data in a DT table with filtering capabilities and detailed modal views for each opportunity. The update database modal allows users to collect new data from official sources but doesn't provide export functionality after collection completes.

Users need to export opportunity data for:
- Offline analysis and reporting
- Integration with external systems
- Sharing with colleagues who don't have platform access
- Archival purposes

The platform already uses writexl for XLSX export in other parts of the codebase, and the data structures are well-defined with 35 columns in the opportunities table.

## Goals / Non-Goals

**Goals:**
- Add download button at top left of results table for exporting filtered data
- Support both XLSX and CSV export formats
- Export only specific columns: Titulo, Entidade, Prazo Limite, Link Portal, Link Detalhes, Link PDF
- Add download options in update database modal after collection completes
- Maintain existing UI/UX patterns and styling
- Ensure exports respect current filters and search results

**Non-Goals:**
- Real-time synchronization of exported data
- Export of raw text content (audit data)
- Export of user-specific data (tracked items, saved searches)
- Custom export templates or formatting options
- Batch export of multiple opportunities with different formats
- Export of all 35 columns from the database

## Decisions

### Decision 1: Export Location and UI Pattern
**Choice:** Add download buttons in two locations:
1. At top left of results table (near Show entries dropdown) for filtered data export
2. In update database modal footer (for post-collection export)

**Rationale:** This provides convenient access points for both use cases without cluttering the interface. The table export respects current filters, while modal export provides immediate access after data collection.

**Alternatives considered:**
- Single export button in navigation: Less discoverable
- Export in each opportunity modal: Too granular for bulk operations
- Separate export page: Overkill for simple download functionality
- Right side of table: User requested top left position

### Decision 2: Export Format Implementation
**Choice:** Use writexl for XLSX and base R for CSV export

**Rationale:** writexl is already a dependency and provides good XLSX formatting. CSV export is straightforward with base R functions. Both formats are widely supported.

**Alternatives considered:**
- openxlsx for XLSX: More features but larger dependency
- Custom CSV formatting: Unnecessary complexity
- JSON export: Not requested and less common for spreadsheet use

### Decision 3: Data Preparation Strategy
**Choice:** Create export-ready data frames that include only these specific columns:
- Titulo (titulo)
- Entidade (entidade)
- Prazo Limite (data_limite)
- Link Portal (link_origem)
- Link Detalhes (link_detalhe)
- Link PDF (link_documento_pdf)

**Rationale:** User requested only essential columns for quick reference and sharing. This keeps exports focused and easy to read.

**Alternatives considered:**
- All 35 columns: Too much data, not user-friendly
- 10-15 columns: Still too many for the use case
- Custom column selection: More complex UI, not requested

### Decision 4: File Naming Convention
**Choice:** Use timestamped filenames: quiiin_export_YYYYMMDD_HHMMSS.xlsx/csv

**Rationale:** Prevents file conflicts and provides clear identification of export timing. Follows common export patterns.

## Risks / Trade-offs

### Risk 1: Large Dataset Performance
**Risk:** Exporting large datasets might cause UI freezing or memory issues
**Mitigation:** Implement export in background process with progress indicator. Limit export to filtered results (already paginated).

### Risk 2: File Format Compatibility
**Risk:** XLSX files might have compatibility issues with older Excel versions
**Mitigation:** Use writexl's default settings which ensure broad compatibility. Provide CSV as alternative.

### Risk 3: User Confusion
**Risk:** Two export locations might confuse users about which to use
**Mitigation:** Clear labeling: Exportar tabela for table button, Baixar dados coletados for modal button. Tooltips explaining differences.

### Risk 4: Data Accuracy
**Risk:** Exported data might not match displayed data due to filtering
**Mitigation:** Export function uses same filtered_results() data source as table display. Clear documentation of what's included.

## Migration Plan

### Phase 1: Core Export Functions
1. Create export utilities in helpers_export.R
2. Test with sample data
3. Verify file format compatibility

### Phase 2: UI Integration
1. Add download buttons to UI at top left position
2. Implement server-side handlers
3. Test user workflows

### Phase 3: Modal Integration
1. Modify update database modal
2. Add post-collection download options
3. Test complete collection-export workflow

### Rollback Strategy
- Remove download buttons from UI
- Keep export functions for potential future use
- No database changes to rollback

## Open Questions

1. Should exports include the search query used to filter results?
2. Should there be a maximum export size limit?
3. Should exports be logged for analytics?
4. Should we add export options for other tables (fundraisers, saved searches)?
