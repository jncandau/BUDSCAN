library(dplyr)
library(lubridate)
library(ggplot2)
library(zoo)
library(tidyr)
library(depmixS4)

# -- Load & prepare data -------------------------------------------------------
read.f <- function(YEAR) {
  read.csv(paste0('XAM_', YEAR, '_07pct.txt'), header = FALSE,
           col.names  = c('datetime', 'pct'),
           colClasses = c('character', 'numeric')) |>
    mutate(datetime = trimws(datetime)) |>
    filter(!is.na(pct), nchar(datetime) == 12) |>
    mutate(dt = ymd_hm(datetime)) |>
    filter(!is.na(dt)) |>
    arrange(dt)
}

YEARS <- 2013:2019

df <- lapply(YEARS, read.f) |> bind_rows()

# Aggregate to hourly means; fill within-year gaps with 0
df_hr <- df |>
  mutate(hr   = floor_date(dt, "hour"),
         year = year(dt)) |>
  group_by(year, hr) |>
  summarise(pct = mean(pct), .groups = "drop") |>
  arrange(hr)

df_hr <- df_hr |>
  group_by(year) |>
  group_modify(function(d, g) {
    all_h <- data.frame(hr = seq(min(d$hr), max(d$hr), by = "hour"))
    left_join(all_h, d, by = "hr") |>
      mutate(across(where(is.numeric), \(x) replace(x, is.na(x), 0)),
             year = g$year)
  }) |>
  ungroup()

# Clamp zeros for Gamma family (must be strictly positive)
df_hr$pct_fit <- pmax(df_hr$pct, 0.001)

# ntimes: number of observations per year (one segment per year for depmixS4)
ntimes_vec <- df_hr |> count(year) |> pull(n) |> as.integer()

# -- Fit 3-state HMM with Gamma emissions --------------------------------------
set.seed(42)
mod <- depmix(
  response = pct_fit ~ 1,
  data     = df_hr,
  nstates  = 3,
  family   = Gamma(link = "log"),
  ntimes   = ntimes_vec
)

fit <- fit(mod, verbose = FALSE)
summary(fit)

# -- Extract results -----------------------------------------------------------
post <- posterior(fit)

# Relabel states by emission mean: state 1 = lowest mean, 3 = highest
state_means <- sapply(1:3, function(k) exp(getpars(fit@response[[k]][[1]])[1]))
ord         <- order(state_means)
state_map   <- integer(3); state_map[ord] <- 1:3
states      <- state_map[post$state]
mu_ord      <- state_means[ord]

cat("State means (%):", round(mu_ord, 3), "\n")
cat("State freq:     ", round(table(states) / nrow(df_hr), 3), "\n")

# Transition matrix (reordered by ascending mean)
A_raw <- t(sapply(1:3, function(k) getpars(fit@transition[[k]])))
A_ord <- A_raw[ord, ord]
cat("\nTransition matrix:\n"); print(round(A_ord, 3))

# -- Plots ---------------------------------------------------------------------
labs <- c("1 - No/background flight", "2 - Moderate flight", "3 - Mass dispersal")
state_cols <- c(
  "1 - No/background flight" = "#a8c5a0",
  "2 - Moderate flight"      = "#c8922a",
  "3 - Mass dispersal"       = "#8b1a1a"
)

plot_df <- df_hr |>
  mutate(pct_raw = pmax(pct, 0),
         state   = factor(states, levels = 1:3, labels = labs))

# Posterior probabilities -- reorder columns to match relabelled states
prob_df <- post[, paste0("S", 1:3)]
colnames(prob_df)[ord] <- labs
prob_df$hr   <- df_hr$hr
prob_df$year <- df_hr$year

# One peak label per day in state 3, per year
peak_df <- plot_df |>
  mutate(year = df_hr$year) |>
  filter(state == "3 - Mass dispersal") |>
  mutate(date = as_date(hr)) |>
  group_by(year, date) |>
  slice_max(pct_raw, n = 1, with_ties = FALSE) |>
  ungroup() |>
  mutate(label = format(date, "%b %d"))

# Time series -- faceted by year
p1 <- ggplot(plot_df |> mutate(year = df_hr$year),
             aes(x = hr, y = pct_raw, color = state)) +
  geom_line(aes(group = 1), alpha = 0.12, color = "grey50", linewidth = 0.3) +
  geom_point(size = 0.5, alpha = 0.6) +
  geom_point(data = peak_df, aes(x = hr, y = pct_raw),
             color = "#8b1a1a", size = 2, shape = 19, inherit.aes = FALSE) +
  geom_text(data = peak_df, aes(x = hr, y = pct_raw, label = label),
            color = "#1a3a2a", vjust = -0.9, hjust = 0.5, size = 2.5,
            fontface = "bold", inherit.aes = FALSE) +
  scale_color_manual(values = state_cols, name = "HMM State") +
  scale_x_datetime(date_labels = "%b %d", date_breaks = "3 weeks") +
  scale_y_continuous(labels = function(v) paste0(v, "%"),
                     expand = expansion(mult = c(0.02, 0.15))) +
  facet_wrap(~ year, ncol = 1, scales = "free_x") +
  labs(
    title    = "Budworm Radar Detections -- HMM State Classification (2013-2019)",
    subtitle = "3-state Gamma HMM (depmixS4)  |  Labels mark daily peak of each mass dispersal event",
    x = NULL, y = "% detections (hourly mean)"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title       = element_text(face = "bold", color = "#1a3a2a"),
    plot.subtitle    = element_text(color = "#555555", size = 9),
    legend.position  = "bottom",
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(color = "#e0ddd5"),
    strip.text       = element_text(face = "bold", color = "#1a3a2a"),
    plot.background  = element_rect(fill = "#f5f2eb", color = NA),
    panel.background = element_rect(fill = "#f5f2eb", color = NA)
  )

# Posterior state probability heatmap -- faceted by year
prob_long <- pivot_longer(prob_df, -c(hr, year),
                          names_to = "state", values_to = "prob") |>
  mutate(state = factor(state, levels = labs))

p3 <- ggplot(prob_long, aes(x = hr, y = state, fill = prob)) +
  geom_raster(interpolate = TRUE) +
  scale_fill_gradientn(
    colors = c("#f5f2eb", "#d4c99a", "#c8922a", "#8b1a1a"),
    name   = "P(state)", limits = c(0, 1)
  ) +
  scale_x_datetime(date_labels = "%b %d", date_breaks = "3 weeks") +
  facet_wrap(~ year, ncol = 1, scales = "free_x") +
  labs(
    title    = "Posterior State Probabilities Over Time (2013-2019)",
    subtitle = "Brighter = model more certain about that state",
    x = NULL, y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title       = element_text(face = "bold", color = "#1a3a2a"),
    plot.subtitle    = element_text(color = "#555555", size = 9),
    panel.grid       = element_blank(),
    strip.text       = element_text(face = "bold", color = "#1a3a2a"),
    plot.background  = element_rect(fill = "#f5f2eb", color = NA),
    panel.background = element_rect(fill = "#f5f2eb", color = NA)
  )

ggsave("hmm_timeseries_2013-2019.png",
       p1, width = 13, height = 4 * length(YEARS), dpi = 150, bg = "#f5f2eb")
ggsave("hmm_state_probs_2013-2019.png",
       p3, width = 13, height = 2.5 * length(YEARS), dpi = 150, bg = "#f5f2eb")
