// Factor the same upper-triangle triplet matrix with Eigen's SimplicialLDLT
// (MPL-2.0, header-only), AMD ordering. Median of 3 factor+solve timings.
#include <Eigen/Sparse>
#include <Eigen/SparseCholesky>
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <fstream>
#include <vector>
int main(int argc, char** argv) {
  for (int a = 1; a < argc; ++a) {
    std::ifstream in(argv[a]);
    int n; in >> n;
    std::vector<Eigen::Triplet<double>> t;
    long i, j; double v;
    while (in >> i >> j >> v) { t.emplace_back(i, j, v); if (i != j) t.emplace_back(j, i, v); }
    Eigen::SparseMatrix<double> A(n, n);
    A.setFromTriplets(t.begin(), t.end());
    Eigen::VectorXd b = Eigen::VectorXd::Ones(n);
    std::vector<double> ts;
    double resid = 0;
    for (int r = 0; r < 3; ++r) {
      auto t0 = std::chrono::steady_clock::now();
      Eigen::SimplicialLDLT<Eigen::SparseMatrix<double>> ldlt(A);
      Eigen::VectorXd x = ldlt.solve(b);
      auto t1 = std::chrono::steady_clock::now();
      ts.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
      resid = (A * x - b).norm() / b.norm();
    }
    std::sort(ts.begin(), ts.end());
    std::printf("%s scalars=%d eigen-simplicial-ldlt=%.1fms residual=%.1e\n", argv[a], n, ts[1], resid);
  }
}
