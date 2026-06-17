# scratch/test_stealth_request.R
library(rvest)
library(xml2)
library(httr2)

source("R/helpers_utils.R")
source("R/helpers_collect.R")

url <- "https://www.google.com"
message("Testing safe_request_page and host alive checks...")

# Test 1: ping online URL
alive <- is_host_alive(url)
message("is_host_alive(online_url): ", alive)
if (!alive) stop("Test failed: online URL detected as offline.")

# Test 2: ping offline URL
dead <- is_host_alive("https://thisurldoesnotexistforreal.xyz")
message("is_host_alive(offline_url): ", dead)
if (dead) stop("Test failed: offline URL detected as online.")

# Test 3: safe_request_page for online URL
res <- safe_request_page(url, use_browser_fallback = FALSE)
message("safe_request_page(online_url) ok: ", res$ok)
if (!res$ok) stop("Test failed: safe_request_page failed for online URL.")

# Test 4: safe_request_page for offline URL
res_dead <- safe_request_page("https://thisurldoesnotexistforreal.xyz", use_browser_fallback = FALSE)
message("safe_request_page(offline_url) ok: ", res_dead$ok)
if (res_dead$ok) stop("Test failed: safe_request_page succeeded for offline URL.")

message("Stealth and scraping resilience test passed successfully!")
