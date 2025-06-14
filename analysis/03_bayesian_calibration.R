# Script running Bayesian calibration

# Load libraries
library(rsofun)
library(dplyr)
library(tidyr)
library(ggplot2)
library(BayesianTools)
library(tictoc)

## Function definitions ----------------------------------------------------------

getSetup <- function(x) {
  classes <- class(x)
  if (any(c('mcmcSampler', 'smcSampler') %in% classes)) x$setup
  else if (any(c('mcmcSamplerList', 'smcSamplerList') %in% classes)) x[[1]]$setup
  else stop('Can not get setup from x')
}

t_col <- function(color, percent = 50, name = NULL) {
  #      color = color name
  #    percent = % transparency
  #       name = an optional name for the color

  ## Get RGB values for named color
  rgb.val <- col2rgb(color)

  ## Make new color using input color as base and alpha set by transparency
  t.col <- rgb(rgb.val[1], rgb.val[2], rgb.val[3],
               max = 255,
               alpha = (100 - percent) * 255 / 100,
               names = name)

  ## Save the color
  invisible(t.col)
}

# Bayesian calibration output
plot_prior_posterior_density <- function(x){

  # Get matrices of prior and posterior samples
  posteriorMat <- getSample(x, parametersOnly = TRUE)
  priorMat <-  getSetup(x)$prior$sampler(10000) # nPriorDraws = 10000

  # Parameter names
  parNames <- colnames(posteriorMat)
  # rename columns priorMat
  colnames(priorMat) <- parNames

  # Create data frame for plotting
  df_plot <- rbind(
    data.frame(posteriorMat, distrib = "posterior"),
    data.frame(priorMat, distrib = "prior")
    )
  df_plot$distrib <- as.factor(df_plot$distrib)

  # Plot with facet wrap
  gg <- df_plot |>
    tidyr::gather(variable, value, kphio:err_gpp) |>
    ggplot(
      aes(x = value, fill = distrib)
    ) +
    geom_density() +
    theme_classic() +
    facet_wrap( ~ variable , nrow = 2, scales = "free") +
    theme(
      legend.position = "bottom",
      axis.title.x = element_text("")
      ) +
    scale_fill_manual(NULL, values = c("#29a274ff", t_col("#777055ff"))) # GECO colors

  return(gg)
}

get_runtime <- function(out_calib) {# function(settings_calib){
  total_time_secs <- sum(unlist(lapply(
    out_calib$mod,
    function(curr_chain){curr_chain$settings$runtime[["elapsed"]]})))
  return(sprintf("Total runtime: %.0f secs", total_time_secs))
}

get_settings_str <- function(out_calib) {

  stopifnot(is(out_calib$mod, "mcmcSamplerList"))

  # explore what's in a mcmcSamplerList:
  # summary(out_calib$mod)
  # plot(out_calib$mod)
  individual_chains <- out_calib$mod
  nrChains <- length(individual_chains) # number of chains

  # plot(individual_chains[[1]]) # chain 1
  # plot(individual_chains[[2]]) # chain 2
  # plot(individual_chains[[3]]) # chain 3
  # class(individual_chains[[1]]$setup); individual_chains[[1]]$setup # Bayesian Setup
  # individual_chains[[1]]$chain
  # individual_chains[[1]]$X
  # individual_chains[[1]]$Z

  nrInternalChains <- lapply(
    individual_chains,
    function(curr_chain){curr_chain$settings$nrChains})  |>
      unlist() |>
      unique() |>
      paste0(collapse = "-")

  nrIterations <- lapply(
    individual_chains,
    function(curr_chain){curr_chain$settings$iterations})|>
      unlist() |>
      unique() |>
      paste0(collapse = "-")

  nrBurnin <- lapply(
    individual_chains,
    function(curr_chain){curr_chain$settings$burnin})    |>
      unlist() |>
      unique() |>
      paste0(collapse = "-")

  sampler_name <- lapply(
    individual_chains,
    function(curr_chain){curr_chain$settings$sampler})   |>
      unlist() |>
      unique() |>
      paste0(collapse = "-")

  # create descriptive string of settings for filename
  return(
    sprintf(
      "Setup-%s-Sampler-%s-%siterations_ofwhich%sburnin_chains_%sx%s_",
      out_calib$name,
      sampler_name,
      nrIterations,
      nrBurnin,
      nrChains,
      nrInternalChains
      )
    )
}

## Read data -------------------------------------------------------------------
# Read data produced with 01_sample_sites.R
drivers <- read_rds(here::here("data/drivers_train.rds"))

# Validation data is in the driver objects (ultimately obtained from FluxDataKit)
validation <- drivers |>
  select(sitename, data = forcing) |>
  mutate(data = purrr::map(data, ~select(., date, gpp)))

## Run calibrations ------------------------------------------------------------

### Global calibration (all sites) ---------------------------------------------
#### Setup s1: global, reduced parameter set, only GPP as target ----------------
settings_calib <- list(
  method = "BayesianTools",
  metric = rsofun::cost_likelihood_pmodel,
  control = list(
    sampler = "DEzs",
    settings = list(
      burnin = 10000,
      iterations = 50000,
      nrChains = 3,       # number of independent chains
      startValue = 3      # number of internal chains to be sampled
    )),
  par = list(
    kphio = list(lower = 0.02, upper = 0.15, init = 0.05),
    kphio_par_a =list(lower = -0.004, upper = -0.001, init = -0.0025),
    kphio_par_b = list(lower = 10, upper = 30, init = 20),
    soilm_thetastar = list(lower = 1, upper = 250, init = 40),
    soilm_betao = list(lower = 0.0, upper = 1.0, init = 0.0),
    err_gpp = list(lower = 0.1, upper = 3, init = 0.8)
  )
)

set.seed(1982)

out <- calib_sofun(
  drivers = drivers,
  obs = validation,
  settings = settings_calib,
  par_fixed = list(
    beta_unitcostratio = 146.0,
    kc_jmax            = 0.41,
    rd_to_vcmax        = 0.014,
    tau_acclim         = 20.0
  ),
  targets = "gpp"
)

out$name <- "s1"
settings_string <- get_settings_str(out)
saveRDS(out, file = here::here(paste0("data/out_calib_", settings_string, ".rds")))

# # Plot MCMC diagnostics
# plot(out$mod)
# summary(out$mod) # Gives Gelman Rubin multivariate of 1.019
# summary(out$par)
# print(get_runtime(out))
#
# # Plot prior and posterior distributions
# gg <- plot_prior_posterior_density(out$mod)
#
# ggsave(here::here("fig/prior_posterior_s1.pdf"), plot = gg, width = 6, height = 5)
# ggsave(here::here("fig/prior_posterior_s1.png"), plot = gg, width = 6, height = 5)

#### Setup s2: global, full parameter set, only GPP as target -------------------
settings_calib <- list(
  method = "BayesianTools",
  metric = rsofun::cost_likelihood_pmodel,
  control = list(
    sampler = "DEzs",
    settings = list(
      burnin = 10000,
      iterations = 50000,
      nrChains = 3,       # number of independent chains
      startValue = 3      # number of internal chains to be sampled
    )),
  par = list(
    kphio = list(lower = 0.02, upper = 0.15, init = 0.05),
    kphio_par_a =list(lower = -0.004, upper = -0.001, init = -0.0025),
    kphio_par_b = list(lower = 10, upper = 30, init = 20),
    soilm_thetastar = list(lower = 1, upper = 250, init = 40),
    soilm_betao = list(lower = 0.0, upper = 1.0, init = 0.0),
    err_gpp = list(lower = 0.1, upper = 3, init = 0.8),
    beta_unitcostratio = list(lower = 50, upper = 250, init = 146.0),
    kc_jmax = list(lower = 0.1, upper = 0.8, init = 0.41),
    tau_acclim = list(lower = 2, upper = 100, init = 20.0)
  )
)

set.seed(1982)

out <- calib_sofun(
  drivers = drivers,
  obs = validation,
  settings = settings_calib,
  par_fixed = list(rd_to_vcmax = 0.014),
  targets = "gpp"
)

out$name <- "s2"
settings_string <- get_settings_str(out)
saveRDS(out, file = here::here(paste0("data/out_calib_", settings_string, ".rds")))

#### Setup s3: global, full parameter set, GPP and traits as target -------------
# Todo:
#   - select target dataset for Vcmax:Jmax and for d13C
#   - derive ci:ca from d13C data
#   - generate driver object for both datasets (using lon, lat info from their sites)
#   - define likelihood function for parallel targets (Vcmax:Jmax, ci:ca, GPP)

# From https://traitecoevo.r-universe.dev/leaf13C
# install.packages('leaf13C', repos = c('https://traitecoevo.r-universe.dev', 'https://cloud.r-project.org'))
# df_d13c <- leaf13C::get_data()





# # Function to run calibration and write output for an individual calibration setup (e.g., by site)
# calib_sofun_bycase <- function(drivers_bycase, settings, case_name = "global"){
#
#   validation_bycase <- drivers_bycase |>
#     select(sitename, data = forcing) |>
#     mutate(data = purrr::map(data, ~select(., date, gpp)))
#
#   # Common calibration settings for all cases
#   settings_calib <- list(
#     method = "BayesianTools",
#     metric = rsofun::cost_likelihood_pmodel,
#     control = list(
#       sampler = "DEzs",
#       settings = list(
#         burnin = 10000,
#         iterations = 50000,
#         nrChains = 3,       # number of independent chains
#         startValue = 3      # number of internal chains to be sampled
#       )),
#     par = list(
#       kphio = list(lower = 0.02, upper = 0.15, init = 0.05),
#       kphio_par_a =list(lower = -0.004, upper = -0.001, init = -0.0025),
#       kphio_par_b = list(lower = 10, upper = 30, init = 20),
#       soilm_thetastar = list(
#         lower = 0.01 * drivers_bycase$site_info[[1]]$whc,
#         upper = 1.0  * drivers_bycase$site_info[[1]]$whc,
#         init  = 0.6  * drivers_bycase$site_info[[1]]$whc
#       ),
#       soilm_betao = list(lower = 0.0, upper = 1.0, init = 0.0),
#       err_gpp = list(lower = 0.1, upper = 3, init = 0.8)
#     )
#   )
#
#   out <- calib_sofun(
#     drivers = drivers_bycase,
#     obs = validation_bycase,
#     settings = settings_calib,
#     par_fixed = list(
#       beta_unitcostratio = 146.0,
#       kc_jmax            = 0.41,
#       rd_to_vcmax        = 0.014,
#       tau_acclim         = 20.0
#       ),
#     targets = "gpp"
#   )
#
#   out$name <- case_name
#
#   settings_string <- get_settings_str(out)
#
#   filnam <- here::here(paste0("data/out_calib_", settings_string, ".rds"))
#
#   saveRDS(out, file = filnam)
#
#   return(filnam)
#
# }
