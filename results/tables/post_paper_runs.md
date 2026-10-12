| benchmark               | scaffold                   | model                | effort   | new_model   | new_scaffold   |   obs_pct |   pred_pct |   abs_err_pp |
|:------------------------|:---------------------------|:---------------------|:---------|:------------|:---------------|----------:|-----------:|-------------:|
| CORE-Bench Hard         | CORE-Agent                 | claude-haiku-4.5     | none     | True        | False          |      11.1 |       32.8 |         21.7 |
| CORE-Bench Hard         | Claude Code                | claude-opus-4.1      | none     | False       | True           |      42.2 |       38.7 |          3.5 |
| CORE-Bench Hard         | Claude Code                | claude-opus-4.5      | none     | True        | True           |      77.8 |       39.4 |         38.4 |
| CORE-Bench Hard         | CORE-Agent                 | claude-opus-4.5      | none     | True        | False          |      42.2 |       33.8 |          8.5 |
| CORE-Bench Hard         | CORE-Agent                 | claude-opus-4.5      | high     | True        | False          |      42.2 |       37.1 |          5.1 |
| CORE-Bench Hard         | CORE-Agent                 | claude-opus-4.5      | none     | True        | False          |      75.6 |       33.8 |         41.8 |
| CORE-Bench Hard         | HAL Generalist Agent       | claude-opus-4.5      | none     | True        | False          |      33.3 |       24.9 |          8.4 |
| CORE-Bench Hard         | HAL Generalist Agent       | claude-opus-4.5      | high     | True        | False          |      31.1 |       28   |          3.1 |
| CORE-Bench Hard         | Claude Code                | claude-sonnet-4      | none     | False       | True           |      46.7 |       36.6 |         10.1 |
| CORE-Bench Hard         | Claude Code                | claude-sonnet-4.5    | none     | True        | True           |      62.2 |       38.1 |         24.1 |
| CORE-Bench Hard         | CORE-Agent                 | gemini-3-pro-preview | high     | True        | False          |      40   |       18.7 |         21.3 |
| CORE-Bench Hard         | HAL Generalist Agent       | gemini-3-pro-preview | high     | True        | False          |      35.6 |       12.1 |         23.5 |
| GAIA                    | HAL Generalist Agent       | claude-haiku-4.5     | none     | True        | False          |      56.4 |       38.9 |         17.5 |
| GAIA                    | HAL Generalist Agent       | claude-sonnet-4.5    | none     | True        | False          |      74.5 |       39.6 |         34.9 |
| GAIA                    | HAL Generalist Agent       | deepseek-v3          | none     | False       | False          |      22.4 |       36.1 |         13.7 |
| Online Mind2Web         | Browser-Use                | claude-haiku-4.5     | none     | True        | False          |      37.7 |       28.9 |          8.8 |
| Online Mind2Web         | Browser-Use                | claude-haiku-4.5     | high     | True        | False          |      40   |       32.5 |          7.5 |
| Online Mind2Web         | SeeAct                     | claude-haiku-4.5     | none     | True        | False          |      32.7 |       28.8 |          3.9 |
| Online Mind2Web         | SeeAct                     | claude-haiku-4.5     | high     | True        | False          |      36.3 |       32.1 |          4.2 |
| Online Mind2Web         | Browser-Use                | claude-sonnet-4.5    | none     | True        | False          |      46.3 |       29.6 |         16.8 |
| Online Mind2Web         | Browser-Use                | claude-sonnet-4.5    | high     | True        | False          |      49.3 |       33.1 |         16.2 |
| Online Mind2Web         | SeeAct                     | claude-sonnet-4.5    | none     | True        | False          |      35   |       29.4 |          5.6 |
| Online Mind2Web         | SeeAct                     | claude-sonnet-4.5    | high     | True        | False          |      38   |       32.7 |          5.3 |
| SWE-bench Verified Mini | HAL Generalist Agent       | claude-haiku-4.5     | high     | True        | False          |      44   |       32.8 |         11.2 |
| SWE-bench Verified Mini | HAL Generalist Agent       | claude-haiku-4.5     | none     | True        | False          |      24   |       29.5 |          5.5 |
| SWE-bench Verified Mini | HAL Generalist Agent       | claude-haiku-4.5     | none     | True        | False          |      24   |       29.5 |          5.5 |
| SWE-bench Verified Mini | SWE-Agent                  | claude-opus-4.1      | none     | False       | False          |      68   |       54.2 |         13.8 |
| SWE-bench Verified Mini | HAL Generalist Agent       | claude-sonnet-4.5    | high     | True        | False          |      40   |       31.4 |          8.6 |
| SWE-bench Verified Mini | HAL Generalist Agent       | claude-sonnet-4.5    | none     | True        | False          |      34   |       28.1 |          5.9 |
| SWE-bench Verified Mini | SWE-Agent                  | claude-sonnet-4.5    | high     | True        | False          |      72   |       59.6 |         12.4 |
| SWE-bench Verified Mini | SWE-Agent                  | claude-sonnet-4.5    | none     | True        | False          |      68   |       56.6 |         11.4 |
| SciCode                 | Scicode Tool Calling Agent | claude-haiku-4.5     | none     | True        | False          |       0   |        7.8 |          7.8 |
| ScienceAgentBench       | SAB Self-Debug             | claude-haiku-4.5     | none     | True        | False          |      18.6 |       32   |         13.4 |
| ScienceAgentBench       | SAB Self-Debug             | claude-haiku-4.5     | high     | True        | False          |      23.5 |       35.2 |         11.7 |
| ScienceAgentBench       | SAB Self-Debug             | claude-sonnet-4.5    | none     | True        | False          |      29.4 |       31.6 |          2.2 |
| ScienceAgentBench       | SAB Self-Debug             | claude-sonnet-4.5    | high     | True        | False          |      30.4 |       34.9 |          4.5 |
| TAU-bench Airline       | TAU-bench Tool Calling     | claude-3.7-sonnet    | none     | False       | True           |      44   |       49.4 |          5.4 |
| TAU-bench Airline       | TAU-bench Tool Calling     | claude-3.7-sonnet    | high     | False       | True           |      52   |       51.4 |          0.6 |
| TAU-bench Airline       | TAU-bench Tool Calling     | claude-opus-4.1      | none     | False       | True           |      50   |       49.4 |          0.6 |
| TAU-bench Airline       | TAU-bench Tool Calling     | claude-opus-4.1      | high     | False       | True           |      52   |       48.5 |          3.5 |
| TAU-bench Airline       | TAU-bench Tool Calling     | deepseek-r1          | default  | False       | True           |      36   |       27.4 |          8.6 |
| TAU-bench Airline       | TAU-bench Tool Calling     | deepseek-v3          | none     | False       | True           |      44   |       33.9 |         10.1 |
| TAU-bench Airline       | TAU-bench Tool Calling     | gemini-2.0-flash     | high     | False       | True           |      28   |       34.2 |          6.2 |
| TAU-bench Airline       | TAU-bench Tool Calling     | gpt-4.1              | none     | False       | True           |      36   |       48.2 |         12.2 |
| TAU-bench Airline       | TAU-bench Tool Calling     | gpt-5                | default  | False       | True           |      48   |       47.2 |          0.8 |
| TAU-bench Airline       | TAU-bench Tool Calling     | o3                   | default  | False       | True           |      54   |       46.6 |          7.4 |
| TAU-bench Airline       | TAU-bench Tool Calling     | o4-mini              | high     | False       | True           |      56   |       49.9 |          6.1 |
| TAU-bench Airline       | TAU-bench Tool Calling     | o4-mini              | low      | False       | True           |      36   |       41.7 |          5.7 |
