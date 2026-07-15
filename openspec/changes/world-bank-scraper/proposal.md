## Why

The World Bank is a major international funding source for development projects in Brazil. Currently, the system does not collect World Bank opportunities, missing significant funding for infrastructure, sustainability, and public sector projects. The World Bank provides procurement notices through a structured website with Excel export capability and an API, making it an ideal candidate for automated collection.

## What Changes

- Add World Bank as a new funding source in the source catalog
- Implement a specialized collector for World Bank procurement notices
- Support Excel download and parsing for structured data extraction
- Implement HTML scraping fallback when Excel is unavailable
- Add API-based collection as secondary fallback (World Bank Projects API)
- Map World Bank fields to the 35-column opportunity schema

## Capabilities

### New Capabilities

- world-bank-source: World Bank source catalog entry and configuration
- world-bank-excel: Excel download and parsing for World Bank procurement notices
- world-bank-api: World Bank Projects API integration as fallback collection method

### Modified Capabilities

- collection-pipeline: Add World Bank collector registration and dispatch

## Impact

- New collector function collect_world_bank() in the collection pipeline
- Addition to source catalog (ontes_financiamento table)
- New R dependencies: eadxl for Excel parsing, httr2 for API calls
- Database schema unchanged (uses existing 35-column opportunidades table)
- Existing collection pipeline extended with new dispatcher entry
