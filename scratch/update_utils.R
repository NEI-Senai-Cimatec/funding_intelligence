utils_path <- "R/helpers_utils.R"
txt <- readLines(utils_path, encoding = "UTF-8", warn = FALSE)

txt <- gsub("Geral / Multicampi", "Sede e Park", txt, fixed = TRUE)
txt <- gsub('c_clean == "Park"', 'c_clean %in% c("Park", "Sede e Park")', txt, fixed = TRUE)
txt <- gsub('return("Park")', 'return("Sede e Park")', txt, fixed = TRUE)
txt <- gsub('is_park <- campi <- c(campi, "Park")', 'is_park <- campi <- c(campi, "Sede e Park")', txt, fixed = TRUE)
txt <- gsub('campi <- c(campi, "Park")', 'campi <- c(campi, "Sede e Park")', txt, fixed = TRUE)

writeLines(txt, utils_path, useBytes = TRUE)
cat("Updated helpers_utils.R successfully\n")
