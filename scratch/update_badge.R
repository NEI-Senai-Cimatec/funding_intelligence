utils_path <- "R/helpers_utils.R"
txt <- readLines(utils_path, encoding = "UTF-8", warn = FALSE)

old_badge <- '"<span class=\'badge\' style=\'background-color:#d97706; color:white; font-size:0.75rem; margin-right:3px;\'>\ud83c\udfed Park</span>"'
new_badge <- '"<span class=\'badge\' style=\'background-color:#004691; color:white; font-size:0.75rem; margin-right:3px;\'><img src=\'logos/logo.png\' alt=\'CIMATEC\' style=\'height:12px; margin-right:4px; vertical-align:middle; filter: brightness(0) invert(1);\'>Sede e Park</span>"'

txt <- gsub("🏭 Park", "<img src='logos/logo.png' alt='CIMATEC' style='height:12px; margin-right:4px; vertical-align:middle; filter: brightness(0) invert(1);'>Sede e Park", txt, fixed = TRUE)

writeLines(txt, utils_path, useBytes = TRUE)
cat("Badge HTML updated successfully\n")
