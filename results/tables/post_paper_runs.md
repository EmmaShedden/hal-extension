| benchmark               | scaffold                   | model                | effort   | new_model   | new_scaffold   |   obs_pct |   pred_pct |   abs_err_pp |
|:------------------------|:---------------------------|:---------------------|:---------|:------------|:---------------|----------:|-----------:|-------------:|
| CORE-Bench Hard         | CORE-Agent                 | claude-haiku-4.5     | none     | True        | False          |      11.1 |       32.9 |         21.8 |
| CORE-Bench Hard         | Claude Code                | claude-opus-4.1      | none     | False       | True           |      42.2 |       37.5 |          4.7 |
| CORE-Bench Hard         | Claude Code                | claude-opus-4.5      | none     | True        | True           |      77.8 |       35.5 |         42.3 |
| CORE-Bench Hard         | CORE-Agent                 | claude-opus-4.5      | none     | True        | False          |      42.2 |       33.8 |          8.4 |
| CORE-Bench Hard         | CORE-Agent                 | claude-opus-4.5      | high     | True        | False          |      42.2 |       34.8 |          7.5 |
| CORE-Bench Hard         | CORE-Agent                 | claude-opus-4.5      | none     | True        | False          |      75.6 |       33.8 |         41.8 |
| CORE-Bench Hard         | HAL Generalist Agent       | claude-opus-4.5      | none     | True        | False          |      33.3 |       24.7 |          8.7 |
| CORE-Bench Hard         | HAL Generalist Agent       | claude-opus-4.5      | high     | True        | False          |      31.1 |       25.6 |          5.5 |
| CORE-Bench Hard         | Claude Code                | claude-sonnet-4      | none     | False       | True           |      46.7 |       31.6 |         15   |
| CORE-Bench Hard         | Claude Code                | claude-sonnet-4.5    | none     | True        | True           |      62.2 |       34.2 |         28   |
| CORE-Bench Hard         | CORE-Agent                 | gemini-3-pro-preview | high     | True        | False          |      40   |       18.1 |         21.9 |
| CORE-Bench Hard         | HAL Generalist Agent       | gemini-3-pro-preview | high     | True        | False          |      35.6 |       11.4 |         24.1 |
| GAIA                    | HAL Generalist Agent       | claude-haiku-4.5     | none     | True        | False          |      56.4 |       44.6 |         11.8 |
| GAIA                    | HAL Generalist Agent       | claude-sonnet-4.5    | none     | True        | False          |      74.5 |       44.9 |         29.6 |
| GAIA                    | HAL Generalist Agent       | deepseek-v3          | none     | False       | False          |      22.4 |       34   |         11.6 |
| Online Mind2Web         | Browser-Use                | claude-haiku-4.5     | none     | True        | False          |      37.7 |       34.4 |          3.3 |
| Online Mind2Web         | Browser-Use                | claude-haiku-4.5     | high     | True        | False          |      40   |       35.5 |          4.5 |
| Online Mind2Web         | SeeAct                     | claude-haiku-4.5     | none     | True        | False          |      32.7 |       33.9 |          1.2 |
| Online Mind2Web         | SeeAct                     | claude-haiku-4.5     | high     | True        | False          |      36.3 |       35   |          1.3 |
| Online Mind2Web         | Browser-Use                | claude-sonnet-4.5    | none     | True        | False          |      46.3 |       34.7 |         11.6 |
| Online Mind2Web         | Browser-Use                | claude-sonnet-4.5    | high     | True        | False          |      49.3 |       35.9 |         13.5 |
| Online Mind2Web         | SeeAct                     | claude-sonnet-4.5    | none     | True        | False          |      35   |       34.2 |          0.8 |
| Online Mind2Web         | SeeAct                     | claude-sonnet-4.5    | high     | True        | False          |      38   |       35.3 |          2.7 |
| SWE-bench Verified Mini | HAL Generalist Agent       | claude-haiku-4.5     | high     | True        | False          |      44   |       31.5 |         12.5 |
| SWE-bench Verified Mini | HAL Generalist Agent       | claude-haiku-4.5     | none     | True        | False          |      24   |       30.5 |          6.5 |
| SWE-bench Verified Mini | HAL Generalist Agent       | claude-haiku-4.5     | none     | True        | False          |      24   |       30.5 |          6.5 |
| SWE-bench Verified Mini | SWE-Agent                  | claude-opus-4.1      | none     | False       | False          |      68   |       55.4 |         12.6 |
| SWE-bench Verified Mini | HAL Generalist Agent       | claude-sonnet-4.5    | high     | True        | False          |      40   |       30.1 |          9.9 |
| SWE-bench Verified Mini | HAL Generalist Agent       | claude-sonnet-4.5    | none     | True        | False          |      34   |       29.1 |          4.9 |
| SWE-bench Verified Mini | SWE-Agent                  | claude-sonnet-4.5    | high     | True        | False          |      72   |       58.6 |         13.4 |
| SWE-bench Verified Mini | SWE-Agent                  | claude-sonnet-4.5    | none     | True        | False          |      68   |       57.6 |         10.4 |
| SciCode                 | Scicode Tool Calling Agent | claude-haiku-4.5     | none     | True        | False          |       0   |        7.9 |          7.9 |
| ScienceAgentBench       | SAB Self-Debug             | claude-haiku-4.5     | none     | True        | False          |      18.6 |       32.3 |         13.6 |
| ScienceAgentBench       | SAB Self-Debug             | claude-haiku-4.5     | high     | True        | False          |      23.5 |       33.2 |          9.7 |
| ScienceAgentBench       | SAB Self-Debug             | claude-sonnet-4.5    | none     | True        | False          |      29.4 |       31.9 |          2.5 |
| ScienceAgentBench       | SAB Self-Debug             | claude-sonnet-4.5    | high     | True        | False          |      30.4 |       32.9 |          2.5 |
| TAU-bench Airline       | TAU-bench Tool Calling     | claude-3.7-sonnet    | none     | False       | True           |      44   |       53.6 |          9.6 |
| TAU-bench Airline       | TAU-bench Tool Calling     | claude-3.7-sonnet    | high     | False       | True           |      52   |       54.9 |          2.9 |
| TAU-bench Airline       | TAU-bench Tool Calling     | claude-opus-4.1      | none     | False       | True           |      50   |       51.5 |          1.5 |
| TAU-bench Airline       | TAU-bench Tool Calling     | claude-opus-4.1      | high     | False       | True           |      52   |       52.8 |          0.8 |
| TAU-bench Airline       | TAU-bench Tool Calling     | deepseek-r1          | default  | False       | True           |      36   |       25.1 |         10.9 |
| TAU-bench Airline       | TAU-bench Tool Calling     | deepseek-v3          | none     | False       | True           |      44   |       30.1 |         13.9 |
| TAU-bench Airline       | TAU-bench Tool Calling     | gemini-2.0-flash     | high     | False       | True           |      28   |       32.5 |          4.5 |
| TAU-bench Airline       | TAU-bench Tool Calling     | gpt-4.1              | none     | False       | True           |      36   |       45.1 |          9.1 |
| TAU-bench Airline       | TAU-bench Tool Calling     | gpt-5                | default  | False       | True           |      48   |       49.4 |          1.4 |
| TAU-bench Airline       | TAU-bench Tool Calling     | o3                   | default  | False       | True           |      54   |       44.5 |          9.5 |
| TAU-bench Airline       | TAU-bench Tool Calling     | o4-mini              | high     | False       | True           |      56   |       42   |         14   |
| TAU-bench Airline       | TAU-bench Tool Calling     | o4-mini              | low      | False       | True           |      36   |       36.7 |          0.7 |
