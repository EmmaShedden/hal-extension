// Minibatch SGD for CPP-style matrix factorisation with factor embeddings (related_methods/DESIGN.md, method 05).
// pred = <p_row, q_col>, p_row = sum of the row's embeddings (id + categorical factors) + Wm^T x_row (numeric factors),
// q_col likewise. Loss: mean squared error over the batch (torch MSELoss), plain SGD, no weight decay.
#include <Rcpp.h>
using namespace Rcpp;

// [[Rcpp::export]]
List sgd_mf(IntegerMatrix Im, NumericMatrix Xm, int nEm, IntegerMatrix Ic, NumericMatrix Xc, int nEc,
            NumericVector y, int d, double lr, int epochs, int batch, double init_sd) {
  int n = y.size(), Km = Im.ncol(), Kc = Ic.ncol(), pm = Xm.ncol(), pc = Xc.ncol();
  NumericMatrix Em(nEm, d), Ec(nEc, d), Wm(pm, d), Wc(pc, d);
  for (int i = 0; i < nEm * d; i++) Em[i] = R::rnorm(0, init_sd);
  for (int i = 0; i < nEc * d; i++) Ec[i] = R::rnorm(0, init_sd);
  for (int i = 0; i < pm * d; i++) Wm[i] = R::rnorm(0, init_sd);
  for (int i = 0; i < pc * d; i++) Wc[i] = R::rnorm(0, init_sd);
  std::vector<int> ord(n); for (int i = 0; i < n; i++) ord[i] = i;
  std::vector<double> P(batch * d), Q(batch * d), G(batch);
  auto vec = [&](int i, IntegerMatrix& I, NumericMatrix& X, NumericMatrix& E, NumericMatrix& W, double* out) {
    for (int k = 0; k < d; k++) {
      double s = 0;
      for (int f = 0; f < I.ncol(); f++) s += E(I(i, f), k);
      for (int f = 0; f < X.ncol(); f++) s += X(i, f) * W(f, k);
      out[k] = s;
    }
  };
  for (int ep = 0; ep < epochs; ep++) {
    for (int i = n - 1; i > 0; i--) { int j = (int) std::floor(R::unif_rand() * (i + 1)); std::swap(ord[i], ord[j]); }
    for (int b0 = 0; b0 < n; b0 += batch) {
      int B = std::min(batch, n - b0);
      for (int t = 0; t < B; t++) {          // forward with parameters fixed for the whole batch
        int i = ord[b0 + t];
        vec(i, Im, Xm, Em, Wm, &P[t * d]); vec(i, Ic, Xc, Ec, Wc, &Q[t * d]);
        double pr = 0; for (int k = 0; k < d; k++) pr += P[t * d + k] * Q[t * d + k];
        G[t] = 2.0 * (pr - y[i]) / B;          // d mean-MSE / d pred
      }
      for (int t = 0; t < B; t++) {          // backward: gradients of the batch loss, then the SGD step
        int i = ord[b0 + t];
        for (int k = 0; k < d; k++) {
          double gp = G[t] * Q[t * d + k], gq = G[t] * P[t * d + k];
          for (int f = 0; f < Km; f++) Em(Im(i, f), k) -= lr * gp;
          for (int f = 0; f < pm; f++) Wm(f, k) -= lr * gp * Xm(i, f);
          for (int f = 0; f < Kc; f++) Ec(Ic(i, f), k) -= lr * gq;
          for (int f = 0; f < pc; f++) Wc(f, k) -= lr * gq * Xc(i, f);
        }
      }
    }
  }
  NumericVector fitted(n);
  std::vector<double> p(d), q(d);
  for (int i = 0; i < n; i++) {
    vec(i, Im, Xm, Em, Wm, p.data()); vec(i, Ic, Xc, Ec, Wc, q.data());
    double s = 0; for (int k = 0; k < d; k++) s += p[k] * q[k]; fitted[i] = s;
  }
  return List::create(_["Em"] = Em, _["Ec"] = Ec, _["Wm"] = Wm, _["Wc"] = Wc, _["fitted"] = fitted);
}
