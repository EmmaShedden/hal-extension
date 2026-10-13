# Fixed-effects IRT by MAP (penalized joint maximum likelihood), shared by methods 01 (Messier) and 02 (Agent
# Psychometrics). Both papers fit point estimates of agent abilities and task difficulties under independent
# Gaussian priors, not a mixed model with estimated variances; MAP with the same priors is the deterministic analogue.
#
#   logit P(y = 1) = a_task * (sum_g theta_g[ability group g of the row] - b_task)
#   1PL: a_task = 1.   2PL: a_task = exp(log_a_task).
#
# abil: named list of factors (one per additive ability component, e.g. list(agent = d$agent) or
#       list(llm = d$llm, scaffold = d$scaffold)); task: factor of tasks; y: 0/1.
# prior_sd: list with theta (scalar or per-component), b, log_a (Gaussian N(mu, sd) priors; mu = 0 except b_mu).
irt_map <- function(y, abil, task, twopl = FALSE, prior_sd = list(theta = 1, b = 1, log_a = 1), b_mu = 0,
                    maxit = 5000) {
  G <- length(abil); nl <- vapply(abil, nlevels, 1L); nt <- nlevels(task)
  idx <- lapply(abil, as.integer); ti <- as.integer(task)
  sd_th <- rep_len(prior_sd$theta, G)
  off <- cumsum(c(0, nl)); np <- off[G + 1] + nt + if (twopl) nt else 0
  unpack <- function(par) {
    th <- lapply(seq_len(G), function(g) par[off[g] + seq_len(nl[g])])
    b <- par[off[G + 1] + seq_len(nt)]
    la <- if (twopl) par[off[G + 1] + nt + seq_len(nt)] else rep(0, nt)
    list(th = th, b = b, la = la)
  }
  eta_parts <- function(P) {
    s <- Reduce(`+`, lapply(seq_len(G), function(g) P$th[[g]][idx[[g]]]))
    a <- exp(P$la[ti]); list(s = s, a = a, eta = a * (s - P$b[ti]))
  }
  fn <- function(par) {
    P <- unpack(par); E <- eta_parts(P)
    nll <- sum(log1p(exp(-abs(E$eta))) + pmax(E$eta, 0) - y * E$eta)
    pen <- sum(vapply(seq_len(G), function(g) sum(P$th[[g]]^2) / (2 * sd_th[g]^2), 0)) +
      sum((P$b - b_mu)^2) / (2 * prior_sd$b^2) + if (twopl) sum(P$la^2) / (2 * prior_sd$log_a^2) else 0
    nll + pen
  }
  gr <- function(par) {
    P <- unpack(par); E <- eta_parts(P)
    r <- plogis(E$eta) - y                                  # d nll / d eta
    g_th <- lapply(seq_len(G), function(g) as.vector(tapply(r * E$a, idx[[g]], sum, default = 0)) + P$th[[g]] / sd_th[g]^2)
    g_b <- as.vector(tapply(-r * E$a, ti, sum, default = 0)) + (P$b - b_mu) / prior_sd$b^2
    out <- c(unlist(g_th), g_b)
    if (twopl) out <- c(out, as.vector(tapply(r * E$a * (E$s - P$b[ti]), ti, sum, default = 0)) + P$la / prior_sd$log_a^2)
    out
  }
  o <- optim(rep(0, np), fn, gr, method = "L-BFGS-B", control = list(maxit = maxit, factr = 1e5))
  P <- unpack(o$par); E <- eta_parts(P)
  list(par = P, p = plogis(E$eta), objective = o$value, convergence = o$convergence, message = o$message,
       loglik = sum(dbinom(y, 1, plogis(E$eta), log = TRUE)), n_params = np,
       levels = c(lapply(abil, levels), list(task = levels(task))))
}

# Check the analytic gradient on a small simulated problem (run once during development).
irt_map_gradcheck <- function() {
  set.seed(1); n <- 400; a <- factor(sample(5, n, TRUE)); s <- factor(sample(3, n, TRUE)); t <- factor(sample(20, n, TRUE))
  y <- rbinom(n, 1, 0.4)
  for (tw in c(FALSE, TRUE)) {
    env <- environment(irt_map); f <- irt_map
    body(f)[[length(body(f))]] <- quote(list(fn = fn, gr = gr, np = np))
    h <- f(y, list(a = a, s = s), t, twopl = tw); par <- rnorm(h$np, 0, 0.3)
    num <- vapply(seq_along(par), function(i) { e <- replace(numeric(length(par)), i, 1e-6); (h$fn(par + e) - h$fn(par - e)) / 2e-6 }, 0)
    cat("twopl =", tw, " max |analytic - numeric| =", max(abs(num - h$gr(par))), "\n")
  }
}
