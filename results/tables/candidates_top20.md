| id   | rd     | bench        | re_opt                                                                               |     AIC |     BIC |   dAIC | singular   | eligible   |
|:-----|:-------|:-------------|:-------------------------------------------------------------------------------------|--------:|--------:|-------:|:-----------|:-----------|
| c030 | linear | domain_slope | (1|model:benchmark) + (1|model:scaffold) + (1|model:effort)                          | 18805.8 | 19013   |    0   | True       | False      |
| c032 | linear | domain_slope | (1|model:benchmark) + (1|scaffold:benchmark) + (1|model:scaffold) + (1|model:effort) | 18805.8 | 19021   |    0   | True       | False      |
| c016 | linear | none         | (1|model:benchmark) + (1|scaffold:benchmark) + (1|model:scaffold) + (1|model:effort) | 18808.1 | 18999.4 |    2.3 | True       | False      |
| c014 | linear | none         | (1|model:benchmark) + (1|model:scaffold) + (1|model:effort)                          | 18808.2 | 18991.5 |    2.4 | True       | False      |
| c062 | log    | domain_slope | (1|model:benchmark) + (1|model:scaffold) + (1|model:effort)                          | 18808.6 | 19015.7 |    2.8 | True       | False      |
| c046 | log    | none         | (1|model:benchmark) + (1|model:scaffold) + (1|model:effort)                          | 18808.9 | 18992.2 |    3.1 | True       | False      |
| c048 | log    | none         | (1|model:benchmark) + (1|scaffold:benchmark) + (1|model:scaffold) + (1|model:effort) | 18810.9 | 19002.1 |    5.1 | True       | False      |
| c023 | linear | domain_slope | (1|model:benchmark) + (1|model:scaffold)                                             | 18812.7 | 19011.9 |    6.9 | True       | False      |
| c064 | log    | domain_slope | (1|model:benchmark) + (1|scaffold:benchmark) + (1|model:scaffold) + (1|model:effort) | 18814.6 | 19029.7 |    8.8 | True       | False      |
| c028 | linear | domain_slope | (1|model:benchmark) + (1|scaffold:benchmark) + (1|model:scaffold)                    | 18814.7 | 19021.9 |    8.9 | True       | False      |
| c012 | linear | none         | (1|model:benchmark) + (1|scaffold:benchmark) + (1|model:scaffold)                    | 18814.8 | 18998.1 |    9   | True       | False      |
| c007 | linear | none         | (1|model:benchmark) + (1|model:scaffold)                                             | 18815.1 | 18990.4 |    9.3 | True       | False      |
| c055 | log    | domain_slope | (1|model:benchmark) + (1|model:scaffold)                                             | 18816.2 | 19015.4 |   10.4 | True       | False      |
| c039 | log    | none         | (1|model:benchmark) + (1|model:scaffold)                                             | 18816.3 | 18991.6 |   10.5 | True       | False      |
| c060 | log    | domain_slope | (1|model:benchmark) + (1|scaffold:benchmark) + (1|model:scaffold)                    | 18818.2 | 19025.4 |   12.4 | True       | False      |
| c044 | log    | none         | (1|model:benchmark) + (1|scaffold:benchmark) + (1|model:scaffold)                    | 18818.3 | 19001.6 |   12.5 | True       | False      |
| c027 | linear | domain_slope | (1|model:scaffold) + (1|model:effort)                                                | 18854   | 19053.2 |   48.2 | False      | True       |
| c059 | log    | domain_slope | (1|model:scaffold) + (1|model:effort)                                                | 18860.2 | 19059.4 |   54.4 | True       | False      |
| c031 | linear | domain_slope | (1|scaffold:benchmark) + (1|model:scaffold) + (1|model:effort)                       | 18860.7 | 19067.8 |   54.9 | True       | False      |
| c020 | linear | domain_slope | (1|model:scaffold)                                                                   | 18861.7 | 19052.9 |   55.8 | True       | False      |
