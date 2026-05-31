library(dplyr)
library(lubridate)
library(ggplot2)
library(zoo)
library(tidyr)
library(depmixS4)

# ── Load & prepare data ───────────────────────────────────────────────────────
read.f <- function(YEAR) {
  read.csv(paste0('XAM_',YEAR,'_07pct.txt'), header=FALSE,
               col.names=c('datetime','pct'),
               colClasses=c('character','numeric')) %>%
  mutate(datetime=trimws(datetime)) %>%
  filter(!is.na(pct), nchar(datetime)==12) %>%
  mutate(dt=with_tz(ymd_hm(datetime, tz="UTC"), tzone="America/New_York")) %>%
  filter(!is.na(dt)) %>%
  arrange(dt)
}

YEAR <- 2019

df <- read.f(YEAR)

# Aggregate to hourly means; fill within-year gaps with 0
df_hr <- df |>
  mutate(hr = floor_date(dt, "hour"),
         year = year(dt)) |>
  group_by(year, hr) |>
  summarise(pct = mean(pct), .groups = "drop") |>
  arrange(hr)

df_hr <- df_hr |>
  group_by(year) |>
  group_modify(function(d, g) {
    all_h  <- data.frame(hr = seq(min(d$hr), max(d$hr), by = "hour"))
    joined <- left_join(all_h, d, by = "hr")
    joined[is.na(joined)] <- 0
    joined
  }) |>
  ungroup()

# Clamp zeros for Gamma family (must be strictly positive)
df_hr$pct_fit <- pmax(df_hr$pct, 0.001)

# ── Fit 3-state HMM with Gamma emissions ─────────────────────────────────────
#   - depmix()     defines the model structure (= initialise mu, sh, A, pi0)
#   - fit()        runs the EM algorithm            (= hmm_em())
#   - posterior()  returns Viterbi states + state probabilities (= states, gamma_mat)

set.seed(42)
mod <- depmix(
  response  = pct_fit ~ 1,        # univariate, intercept-only emission
  data      = df_hr,
  nstates   = 3,
  family    = Gamma(link="log"),   # Gamma emissions, log link for mean parameter
  ntimes    = nrow(df_hr)          # single continuous sequence
)

fit <- fit(mod, verbose=FALSE)
summary(fit)

# ── Extract results ───────────────────────────────────────────────────────────
post    <- posterior(fit)          # data.frame: $state (Viterbi), $S1/$S2/$S3 (posteriors)
states  <- post$state

# Relabel states by mean so state 1 = lowest, 3 = highest
# (depmixS4 labels are arbitrary; we sort by fitted emission mean)
get_gamma_mean <- function(fit, k) {
  # For Gamma(link="log"), the intercept is log(mean)
  exp(getpars(fit)[ grep(paste0("St",k,".*Re1.*Int"), names(getpars(fit))) ])
}
# Extract emission means via named parameter vector
# For Gamma(link="log"), the intercept parameter is log(mean)
all_pars <- getpars(fit)
state_means <- sapply(1:3, function(k) {
  resp <- getpars(fit@response[[k]][[1]])
  exp(resp["(Intercept)"])
})

ord       <- order(state_means)
state_map <- integer(3); state_map[ord] <- 1:3
states    <- state_map[post$state]
mu_ord    <- state_means[ord]

cat("State means (%):", round(mu_ord, 3), "\n")
cat("State freq:     ", round(table(states)/nrow(df_hr), 3), "\n")

# Transition matrix (rows = from, cols = to), reordered
A_raw <- matrix(getpars(fit)[1:9], 3, 3, byrow=TRUE)  # first 9 params = transition probs
A_ord <- A_raw[ord, ord]
cat("\nTransition matrix:\n"); print(round(A_ord, 3))

# ── Plots (identical to custom implementation) ────────────────────────────────
labs       <- c("1 - No/background flight","2 - Moderate flight","3 - Mass dispersal")
state_cols <- c("1 - No/background flight"="#a8c5a0",
                "2 - Moderate flight"="#c8922a",
                "3 - Mass dispersal"="#8b1a1a")

plot_df <- df_hr %>%
  mutate(pct_raw=pmax(pct,0),
         state=factor(states, levels=1:3, labels=labs))

# Posterior probabilities (reorder columns to match relabelled states)
prob_df           <- post[, paste0("S", 1:3)]
colnames(prob_df) <- labs[state_map]   # map depmixS4 state indices to our labels
prob_df$hr        <- df_hr$hr

# One peak label per day: true daily max, only on days with a state-3 hour
state3_dates <- plot_df %>%
  filter(state == "3 - Mass dispersal") %>%
  mutate(date = as_date(hr)) %>%
  distinct(date)

peak_df <- plot_df %>%
  mutate(date = as_date(hr)) %>%
  semi_join(state3_dates, by = "date") %>%
  group_by(date) %>%
  slice_max(pct_raw, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  mutate(label = format(date, "%b %d"))

# Time series plot
p1 <- ggplot(plot_df, aes(x=hr, y=pct_raw, color=state)) +
  geom_point(size=0.6, alpha=0.6) +
  geom_line(aes(group=1), alpha=0.12, color="grey50", linewidth=0.3) +
  geom_point(data=peak_df, aes(x=hr, y=pct_raw),
             color="#8b1a1a", size=2.5, shape=19, inherit.aes=FALSE) +
  geom_text(data=peak_df, aes(x=hr, y=pct_raw, label=label),
            color="#1a3a2a", vjust=-0.9, hjust=0.5, size=2.8, fontface="bold",
            inherit.aes=FALSE) +
  scale_color_manual(values=state_cols, name="HMM State") +
  scale_x_datetime(date_labels="%b %d", date_breaks="2 weeks") +
  scale_y_continuous(labels=function(v) paste0(v,"%"),
                     expand=expansion(mult=c(0.02, 0.15))) +
  labs(title=paste0("Budworm Radar Detections — HMM State Classification (", YEAR, ")"),
       subtitle="3-state Gamma HMM (depmixS4)  |  Labels mark daily peak of each mass dispersal event",
       x=NULL, y="% detections (hourly mean)") +
  theme_minimal(base_size=13) +
  theme(plot.title=element_text(face="bold", color="#1a3a2a"),
        plot.subtitle=element_text(color="#555555", size=10),
        legend.position="bottom",
        panel.grid.minor=element_blank(),
        panel.grid.major=element_line(color="#e0ddd5"),
        plot.background=element_rect(fill="#f5f2eb", color=NA),
        panel.background=element_rect(fill="#f5f2eb", color=NA))

# Posterior state probability heatmap
prob_long <- pivot_longer(prob_df, -hr, names_to="state", values_to="prob") %>%
             mutate(state=factor(state, levels=labs))

p3 <- ggplot(prob_long, aes(x=hr, y=state, fill=prob)) +
  geom_raster(interpolate=TRUE) +
  scale_fill_gradientn(colors=c("#f5f2eb","#d4c99a","#c8922a","#8b1a1a"),
                       name="P(state)", limits=c(0,1)) +
  scale_x_datetime(date_labels="%b %d", date_breaks="2 weeks") +
  labs(title="Posterior State Probabilities Over Time",
       subtitle="Brighter = model more certain about that state",
       x=NULL, y=NULL) +
  theme_minimal(base_size=12) +
  theme(plot.title=element_text(face="bold", color="#1a3a2a"),
        plot.subtitle=element_text(color="#555555", size=10),
        panel.grid=element_blank(),
        plot.background=element_rect(fill="#f5f2eb", color=NA),
        panel.background=element_rect(fill="#f5f2eb", color=NA))

ggsave(paste0("hmm_timeseries_", YEAR, ".png"),  p1, width=13, height=5.5, dpi=150, bg="#f5f2eb")
ggsave(paste0("hmm_state_probs_", YEAR, ".png"), p3, width=13, height=3.5, dpi=150, bg="#f5f2eb")

events <- read_excel(
  "/Users/jn/Library/CloudStorage/Dropbox/Projects/CFS/SBW Radar/BUDSCAN/Potential dispersal events in Eastern Canada 2013-2024.xlsx",
  sheet     = "Sheet1",
  skip      = 1,                          # row 1 is the header row
  col_names = c("StartDate", "EndDate", "LocationName", "Latitude", "Longitude",
                "Radar", "JennieRadar", "Visual", "LightTrap", "PheromoneTrap",
                "Reference", "Notes"),
  col_types = c("date", "date", "text", "numeric", "numeric",
                "text", "text", "text", "text", "text", "text", "text")
) |>
  mutate(
    StartDate = as_date(StartDate),
    EndDate   = as_date(EndDate),
    year      = year(StartDate)
  ) |>
  filter(year %in% 2013:2019)

# For each peak, check if its date falls within [StartDate, EndDate] of any event
matches <- peak_df |>
  rowwise() |>
  mutate(
    matched = any(date >= events$StartDate & date <= events$EndDate, na.rm = TRUE),
    event_locations = {
      idx <- which(date >= events$StartDate & date <= events$EndDate)
      if (length(idx) == 0) NA_character_
      else paste(events$LocationName[idx], collapse = "; ")
    },
    event_start = {
      idx <- which(date >= events$StartDate & date <= events$EndDate)
      if (length(idx) == 0) NA_character_
      else paste(as.character(events$StartDate[idx]), collapse = "; ")
    },
    event_end = {
      idx <- which(date >= events$StartDate & date <= events$EndDate)
      if (length(idx) == 0) NA_character_
      else paste(as.character(events$EndDate[idx]), collapse = "; ")
    }
  ) |>
  ungroup()

matches |>
  filter(matched) |>
  dplyr::select(year, date, pct_raw, event_locations, event_start, event_end) |>
  arrange(date)
