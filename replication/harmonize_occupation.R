# The supplied file applies the pre-redesign labels to raw P6430 in every year.
# Marco 2018 uses 7 = day laborer and 8 = other, including its 2021 parallel.
occupation_harmonization_version <- "P6430-framework-2026-10-11-v1"
harmonize_occupation <- function(d) {
  if (identical(attr(d, "occupation_harmonization"), occupation_harmonization_version)) return(d)
  old_labels <- c("Obrero o empleado de empresa particular", "Obrero o empleado del gobierno",
    "Empleado dom\u00e9stico", "Trabajador por cuenta propia", "Patr\u00f3n o empleador",
    "Trabajador familiar sin remuneraci\u00f3n", "Trabajador sin remuneraci\u00f3n en otros hogares",
    "Jornalero o pe\u00f3n", "Otro")
  raw_code <- match(as.character(d$posicion_ocupacional_label), old_labels)
  stopifnot(!anyNA(raw_code))
  if ("posicion_ocupacional" %in% names(d)) stopifnot(all(raw_code == as.numeric(d$posicion_ocupacional)))
  year <- as.integer(as.character(d$anio))
  stopifnot(!anyNA(year), !any(year == 2020), !any(year >= 2021 & raw_code == 9))
  code <- raw_code
  code[year >= 2021 & raw_code == 7] <- 8L
  code[year >= 2021 & raw_code == 8] <- 9L
  d$occupation_raw_code <- raw_code
  d$occupation_harmonized_code <- code
  d$posicion_ocupacional_label <- factor(old_labels[code])
  d$wage_employee <- code %in% c(1L, 2L, 3L, 8L)
  attr(d, "occupation_harmonization") <- occupation_harmonization_version
  d
}
