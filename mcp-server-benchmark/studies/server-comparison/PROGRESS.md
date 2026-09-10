2026-08-10 16:34:42 | === MCP 서버 본측정 시작 (통과 2종 즉시, 실패 2종 복구 시도 병행) ===
2026-08-10 16:34:42 | START containers / r1
2026-08-10 17:25:25 | END   containers / r1 (rc=0, 3043s)
2026-08-10 17:25:25 | START flux159 / r1
2026-08-10 18:27:21 | END   flux159 / r1 (rc=0, 3716s)
2026-08-10 18:27:21 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-10 18:27:47 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-10 18:28:07 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-10 18:28:49 | 복구 시도 aks: npx -y aks-mcp
2026-08-10 18:29:12 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-10 18:29:26 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-10 18:30:08 | --- r1 완료 (참여 서버 2종) ---
2026-08-10 18:30:08 | START containers / r2
2026-08-10 19:18:05 | END   containers / r2 (rc=0, 2877s)
2026-08-10 19:18:05 | START flux159 / r2
2026-08-10 20:02:38 | END   flux159 / r2 (rc=0, 2673s)
2026-08-10 20:02:38 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-10 20:03:06 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-10 20:03:20 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-10 20:03:36 | 복구 시도 aks: npx -y aks-mcp
2026-08-10 20:03:53 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-10 20:04:04 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-10 20:04:46 | --- r2 완료 (참여 서버 2종) ---
2026-08-10 20:04:46 | START containers / r3
2026-08-10 21:00:17 | END   containers / r3 (rc=0, 3331s)
2026-08-10 21:00:17 | START flux159 / r3
2026-08-10 21:48:39 | END   flux159 / r3 (rc=0, 2902s)
2026-08-10 21:48:39 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-10 21:49:31 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-10 21:50:03 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-10 21:50:19 | 복구 시도 aks: npx -y aks-mcp
2026-08-10 21:50:36 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-10 21:50:44 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-10 21:51:16 | --- r3 완료 (참여 서버 2종) ---
2026-08-10 21:51:16 | === MCP 본측정 종료 (최종 참여 2종) ===
2026-08-10 21:55:08 | === MCP 서버 본측정 시작 (통과 2종 즉시, 실패 2종 복구 시도 병행) ===
2026-08-10 21:55:08 | START containers / r1
2026-08-10 22:43:05 | END   containers / r1 (rc=0, 2877s)
2026-08-10 22:43:05 | START flux159 / r1
2026-08-10 23:30:09 | END   flux159 / r1 (rc=0, 2824s)
2026-08-10 23:30:09 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-10 23:30:43 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-10 23:31:19 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-10 23:31:38 | 복구 시도 aks: npx -y aks-mcp
2026-08-10 23:31:47 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-10 23:31:54 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-10 23:32:12 | --- r1 완료 (참여 서버 2종) ---
2026-08-10 23:32:12 | START containers / r2
2026-08-11 00:46:29 | END   containers / r2 (rc=0, 4457s)
2026-08-11 00:46:29 | START flux159 / r2
2026-08-11 01:43:17 | END   flux159 / r2 (rc=0, 3408s)
2026-08-11 01:43:17 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-11 01:43:44 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-11 01:44:13 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-11 01:44:43 | 복구 시도 aks: npx -y aks-mcp
2026-08-11 01:45:43 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-11 01:46:09 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-11 01:46:23 | --- r2 완료 (참여 서버 2종) ---
2026-08-11 01:46:23 | START containers / r3
2026-08-11 02:52:30 | END   containers / r3 (rc=0, 3967s)
2026-08-11 02:52:30 | START flux159 / r3
2026-08-11 03:57:48 | END   flux159 / r3 (rc=0, 3918s)
2026-08-11 03:57:49 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-11 03:58:10 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-11 03:58:21 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-11 03:58:42 | 복구 시도 aks: npx -y aks-mcp
2026-08-11 03:58:57 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-11 03:59:12 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-11 03:59:27 | --- r3 완료 (참여 서버 2종) ---
2026-08-11 03:59:27 | === MCP 본측정 종료 (최종 참여 2종) ===
2026-08-11 04:05:09 | === MCP 서버 본측정 시작 (통과 2종 즉시, 실패 2종 복구 시도 병행) ===
2026-08-11 04:05:09 | START containers / r1
2026-08-11 05:07:17 | END   containers / r1 (rc=0, 3728s)
2026-08-11 05:07:18 | START flux159 / r1
2026-08-11 05:57:58 | END   flux159 / r1 (rc=0, 3040s)
2026-08-11 05:57:58 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-11 05:58:34 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-11 05:59:11 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-11 05:59:31 | 복구 시도 aks: npx -y aks-mcp
2026-08-11 05:59:50 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-11 06:00:07 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-11 06:00:38 | --- r1 완료 (참여 서버 2종) ---
2026-08-11 06:00:38 | START containers / r2
2026-08-11 06:59:09 | END   containers / r2 (rc=0, 3511s)
2026-08-11 06:59:09 | START flux159 / r2
2026-08-11 07:58:56 | END   flux159 / r2 (rc=0, 3587s)
2026-08-11 07:58:56 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-11 07:59:49 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-11 08:00:08 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-11 08:00:24 | 복구 시도 aks: npx -y aks-mcp
2026-08-11 08:00:43 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-11 08:01:04 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-11 08:01:23 | --- r2 완료 (참여 서버 2종) ---
2026-08-11 08:01:23 | START containers / r3
2026-08-11 08:56:45 | END   containers / r3 (rc=0, 3322s)
2026-08-11 08:56:46 | START flux159 / r3
2026-08-11 09:43:55 | END   flux159 / r3 (rc=0, 2829s)
2026-08-11 09:43:55 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-11 09:44:19 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-11 09:44:38 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-11 09:45:03 | 복구 시도 aks: npx -y aks-mcp
2026-08-11 09:45:17 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-11 09:45:41 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-11 09:46:01 | --- r3 완료 (참여 서버 2종) ---
2026-08-11 09:46:01 | === MCP 본측정 종료 (최종 참여 2종) ===
2026-08-11 09:55:11 | === MCP 서버 본측정 시작 (통과 2종 즉시, 실패 2종 복구 시도 병행) ===
2026-08-11 09:55:11 | START containers / r1
2026-08-11 10:45:43 | END   containers / r1 (rc=0, 3032s)
2026-08-11 10:45:43 | START flux159 / r1
2026-08-11 11:39:34 | END   flux159 / r1 (rc=0, 3231s)
2026-08-11 11:39:34 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-11 11:39:51 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-11 11:40:01 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-11 11:40:18 | 복구 시도 aks: npx -y aks-mcp
2026-08-11 11:40:53 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-11 11:41:18 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-11 11:41:31 | --- r1 완료 (참여 서버 2종) ---
2026-08-11 11:41:31 | START containers / r2
2026-08-11 12:29:51 | END   containers / r2 (rc=0, 2900s)
2026-08-11 12:29:52 | START flux159 / r2
2026-08-11 13:14:05 | END   flux159 / r2 (rc=0, 2653s)
2026-08-11 13:14:06 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-11 13:14:29 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-11 13:14:47 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-11 13:14:58 | 복구 시도 aks: npx -y aks-mcp
2026-08-11 13:15:07 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-11 13:15:24 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-11 13:15:51 | --- r2 완료 (참여 서버 2종) ---
2026-08-11 13:15:51 | START containers / r3
2026-08-11 14:23:18 | END   containers / r3 (rc=0, 4047s)
2026-08-11 14:23:19 | START flux159 / r3
2026-08-11 15:22:51 | END   flux159 / r3 (rc=0, 3572s)
2026-08-11 15:22:51 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-11 15:23:17 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-11 15:23:33 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-11 15:23:43 | 복구 시도 aks: npx -y aks-mcp
2026-08-11 15:24:10 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-11 15:24:25 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-11 15:24:56 | --- r3 완료 (참여 서버 2종) ---
2026-08-11 15:24:56 | === MCP 본측정 종료 (최종 참여 2종) ===
2026-08-11 15:25:12 | === MCP 서버 본측정 시작 (통과 2종 즉시, 실패 2종 복구 시도 병행) ===
2026-08-11 15:25:12 | START containers / r1
2026-08-11 16:18:48 | END   containers / r1 (rc=0, 3216s)
2026-08-11 16:18:48 | START flux159 / r1
2026-08-11 17:06:11 | END   flux159 / r1 (rc=0, 2843s)
2026-08-11 17:06:11 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-11 17:06:47 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-11 17:08:04 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-11 17:08:29 | 복구 시도 aks: npx -y aks-mcp
2026-08-11 17:08:46 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-11 17:08:55 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-11 17:09:16 | --- r1 완료 (참여 서버 2종) ---
2026-08-11 17:09:16 | START containers / r2
2026-08-11 18:08:10 | END   containers / r2 (rc=0, 3534s)
2026-08-11 18:08:10 | START flux159 / r2
2026-08-11 18:55:48 | END   flux159 / r2 (rc=0, 2858s)
2026-08-11 18:55:48 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-11 18:56:05 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-11 18:56:23 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-11 18:56:33 | 복구 시도 aks: npx -y aks-mcp
2026-08-11 18:57:05 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-11 18:57:32 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-11 18:58:05 | --- r2 완료 (참여 서버 2종) ---
2026-08-11 18:58:05 | START containers / r3
2026-08-11 19:45:59 | END   containers / r3 (rc=0, 2874s)
2026-08-11 19:45:59 | START flux159 / r3
2026-08-11 20:31:39 | END   flux159 / r3 (rc=0, 2740s)
2026-08-11 20:31:39 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-11 20:32:04 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-11 20:32:24 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-11 20:32:39 | 복구 시도 aks: npx -y aks-mcp
2026-08-11 20:32:53 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-11 20:33:14 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-11 20:33:48 | --- r3 완료 (참여 서버 2종) ---
2026-08-11 20:33:48 | === MCP 본측정 종료 (최종 참여 2종) ===
2026-08-11 20:35:13 | === MCP 서버 본측정 시작 (통과 2종 즉시, 실패 2종 복구 시도 병행) ===
2026-08-11 20:35:13 | START containers / r1
2026-08-11 21:50:15 | END   containers / r1 (rc=0, 4502s)
2026-08-11 21:50:15 | START flux159 / r1
2026-08-11 22:42:19 | END   flux159 / r1 (rc=0, 3124s)
2026-08-11 22:42:19 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-11 22:42:41 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-11 22:42:58 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-11 22:43:21 | 복구 시도 aks: npx -y aks-mcp
2026-08-11 22:44:07 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-11 22:44:35 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-11 22:44:52 | --- r1 완료 (참여 서버 2종) ---
2026-08-11 22:44:52 | START containers / r2
2026-08-11 23:54:20 | END   containers / r2 (rc=0, 4168s)
2026-08-11 23:54:20 | START flux159 / r2
2026-08-12 00:48:39 | END   flux159 / r2 (rc=0, 3259s)
2026-08-12 00:48:39 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-12 00:49:04 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-12 00:49:23 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-12 00:49:40 | 복구 시도 aks: npx -y aks-mcp
2026-08-12 00:50:08 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-12 00:50:29 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-12 00:50:47 | --- r2 완료 (참여 서버 2종) ---
2026-08-12 00:50:47 | START containers / r3
2026-08-12 01:59:50 | END   containers / r3 (rc=0, 4143s)
2026-08-12 01:59:50 | START flux159 / r3
2026-08-12 02:41:44 | END   flux159 / r3 (rc=0, 2514s)
2026-08-12 02:41:44 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-12 02:42:05 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-12 02:43:13 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-12 02:43:51 | 복구 시도 aks: npx -y aks-mcp
2026-08-12 02:44:10 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-12 02:44:30 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-12 02:44:55 | --- r3 완료 (참여 서버 2종) ---
2026-08-12 02:44:55 | === MCP 본측정 종료 (최종 참여 2종) ===
2026-08-12 02:45:15 | === MCP 서버 본측정 시작 (통과 2종 즉시, 실패 2종 복구 시도 병행) ===
2026-08-12 02:45:15 | START containers / r1
2026-08-12 04:19:35 | END   containers / r1 (rc=0, 5660s)
2026-08-12 04:19:35 | START flux159 / r1
2026-08-12 05:18:30 | END   flux159 / r1 (rc=0, 3535s)
2026-08-12 05:18:30 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-12 05:19:33 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-12 05:20:44 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-12 05:20:58 | 복구 시도 aks: npx -y aks-mcp
2026-08-12 05:21:08 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-12 05:21:18 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-12 05:22:12 | --- r1 완료 (참여 서버 2종) ---
2026-08-12 05:22:12 | START containers / r2
2026-08-12 06:22:09 | END   containers / r2 (rc=0, 3597s)
2026-08-12 06:22:09 | START flux159 / r2
2026-08-12 07:12:10 | END   flux159 / r2 (rc=0, 3001s)
2026-08-12 07:12:10 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-12 07:13:27 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-12 07:13:51 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-12 07:14:11 | 복구 시도 aks: npx -y aks-mcp
2026-08-12 07:14:26 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-12 07:15:05 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-12 07:15:26 | --- r2 완료 (참여 서버 2종) ---
2026-08-12 07:15:26 | START containers / r3
2026-08-12 08:12:30 | END   containers / r3 (rc=0, 3424s)
2026-08-12 08:12:30 | START flux159 / r3
2026-08-12 08:57:00 | END   flux159 / r3 (rc=0, 2670s)
2026-08-12 08:57:00 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-12 08:57:43 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-12 08:58:05 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-12 08:58:23 | 복구 시도 aks: npx -y aks-mcp
2026-08-12 08:58:57 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-12 08:59:18 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-12 08:59:37 | --- r3 완료 (참여 서버 2종) ---
2026-08-12 08:59:37 | === MCP 본측정 종료 (최종 참여 2종) ===
2026-08-12 09:05:17 | === MCP 서버 본측정 시작 (통과 2종 즉시, 실패 2종 복구 시도 병행) ===
2026-08-12 09:05:17 | START containers / r1
2026-08-12 10:01:05 | END   containers / r1 (rc=0, 3348s)
2026-08-12 10:01:05 | START flux159 / r1
2026-08-12 10:50:17 | END   flux159 / r1 (rc=0, 2952s)
2026-08-12 10:50:17 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-12 10:51:17 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-12 10:51:47 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-12 10:52:00 | 복구 시도 aks: npx -y aks-mcp
2026-08-12 10:52:21 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-12 10:52:50 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-12 10:53:05 | --- r1 완료 (참여 서버 2종) ---
2026-08-12 10:53:05 | START containers / r2
2026-08-12 11:51:45 | END   containers / r2 (rc=0, 3520s)
2026-08-12 11:51:45 | START flux159 / r2
2026-08-12 12:41:05 | END   flux159 / r2 (rc=0, 2960s)
2026-08-12 12:41:05 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-12 12:41:21 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-12 12:41:39 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-12 12:42:02 | 복구 시도 aks: npx -y aks-mcp
2026-08-12 12:42:23 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-12 12:42:33 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-12 12:43:16 | --- r2 완료 (참여 서버 2종) ---
2026-08-12 12:43:16 | START containers / r3
2026-08-12 13:36:48 | END   containers / r3 (rc=0, 3212s)
2026-08-12 13:36:48 | START flux159 / r3
2026-08-12 14:21:46 | END   flux159 / r3 (rc=0, 2698s)
2026-08-12 14:21:47 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-12 14:22:19 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-12 14:22:46 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-12 14:23:06 | 복구 시도 aks: npx -y aks-mcp
2026-08-12 14:23:24 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-12 14:23:38 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-12 14:24:05 | --- r3 완료 (참여 서버 2종) ---
2026-08-12 14:24:05 | === MCP 본측정 종료 (최종 참여 2종) ===
2026-08-12 14:25:16 | === MCP 서버 본측정 시작 (통과 2종 즉시, 실패 2종 복구 시도 병행) ===
2026-08-12 14:25:16 | START containers / r1
2026-08-12 15:09:40 | END   containers / r1 (rc=0, 2664s)
2026-08-12 15:09:40 | START flux159 / r1
2026-08-12 16:03:44 | END   flux159 / r1 (rc=0, 3244s)
2026-08-12 16:03:44 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-12 16:04:01 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-12 16:04:17 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-12 16:04:29 | 복구 시도 aks: npx -y aks-mcp
2026-08-12 16:04:41 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-12 16:04:57 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-12 16:05:16 | --- r1 완료 (참여 서버 2종) ---
2026-08-12 16:05:16 | START containers / r2
2026-08-12 17:00:54 | END   containers / r2 (rc=0, 3338s)
2026-08-12 17:00:54 | START flux159 / r2
2026-08-12 17:50:48 | END   flux159 / r2 (rc=0, 2994s)
2026-08-12 17:50:48 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-12 17:51:26 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-12 17:51:44 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-12 17:52:17 | 복구 시도 aks: npx -y aks-mcp
2026-08-12 17:52:34 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-12 17:52:52 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-12 17:53:21 | --- r2 완료 (참여 서버 2종) ---
2026-08-12 17:53:21 | START containers / r3
2026-08-12 19:10:27 | END   containers / r3 (rc=0, 4626s)
2026-08-12 19:10:27 | START flux159 / r3
2026-08-12 20:52:30 | END   flux159 / r3 (rc=0, 6123s)
2026-08-12 20:52:30 | 복구 시도 rohitg00: uvx --from kubectl-mcp-tool kubectl-mcp
2026-08-12 20:53:56 | 복구 시도 rohitg00: pipx run kubectl-mcp-tool
2026-08-12 20:54:09 | 복구 시도 rohitg00: python3 -m kubectl_mcp_tool
2026-08-12 20:54:25 | 복구 시도 aks: npx -y aks-mcp
2026-08-12 20:54:48 | 복구 시도 aks: npx -y @azure/aks-mcp-server
2026-08-12 20:55:07 | 복구 시도 aks: npx -y azure-aks-mcp
2026-08-12 20:55:28 | --- r3 완료 (참여 서버 2종) ---
2026-08-12 20:55:28 | === MCP 본측정 종료 (최종 참여 2종) ===
2026-08-12 21:05:20 | === MCP 서버 본측정 시작 (통과 2종 즉시, 실패 2종 복구 시도 병행) ===
2026-08-12 21:05:20 | START containers / r1
2026-08-12 22:35:17 | END   containers / r1 (rc=0, 5397s)
2026-08-12 22:35:17 | START flux159 / r1
2026-08-12 23:19:55 | END   flux159 / r1 (rc=0, 2678s)
2026-08-12 23:19:55 | --- r1 완료 (참여 서버 2종) ---
2026-08-12 23:19:55 | STOP 마감 도달, containers/r2 생략
2026-08-12 23:19:55 | STOP 마감 도달, flux159/r2 생략
2026-08-12 23:19:55 | --- r2 완료 (참여 서버 2종) ---
2026-08-12 23:19:55 | STOP 마감 도달, containers/r3 생략
2026-08-12 23:19:55 | STOP 마감 도달, flux159/r3 생략
2026-08-12 23:19:55 | --- r3 완료 (참여 서버 2종) ---
2026-08-12 23:19:55 | === MCP 본측정 종료 (최종 참여 2종) ===
2026-08-18 13:42:02 | === MCP 서버 2차 측정 시작 (신규 4종) ===
2026-08-18 13:42:02 | 사전 준비 시작
2026-08-18 13:43:39 |   mcp-kubernetes 확보
2026-08-18 13:45:12 |   uvx 캐시 완료
2026-08-18 13:45:12 |   npx 캐시 시도 완료
2026-08-18 13:45:12 | 사전 준비 종료
2026-08-18 13:45:12 | --- azure-k8s 스모크: $HOME/.local/bin/mcp-kubernetes --access-level readwrite
2026-08-18 13:45:25 |   스모크 통과
2026-08-18 13:45:25 | START azure-k8s / r1
2026-08-18 16:33:47 | END   azure-k8s / r1 (rc=0, 10102s)
2026-08-18 16:33:47 | START azure-k8s / r2
2026-08-18 18:45:04 | END   azure-k8s / r2 (rc=0, 7877s)
2026-08-18 18:45:04 | START azure-k8s / r3
2026-08-18 21:36:53 | END   azure-k8s / r3 (rc=0, 10309s)
2026-08-18 21:36:53 | --- rohitg00 스모크: uvx --from kubectl-mcp-server kubectl-mcp-serve serve --transport stdio
2026-08-18 21:38:30 |   스모크 통과
2026-08-18 21:38:30 | START rohitg00 / r1
2026-08-19 00:22:19 | END   rohitg00 / r1 (rc=0, 9829s)
2026-08-19 00:22:19 | START rohitg00 / r2
2026-08-19 02:54:16 | END   rohitg00 / r2 (rc=0, 9117s)
2026-08-19 02:54:16 | START rohitg00 / r3
2026-08-19 05:31:10 | END   rohitg00 / r3 (rc=0, 9414s)
2026-08-19 05:31:10 | --- ro-only 스모크: npx -y @patrickdappollonio/mcp-kubernetes-ro
2026-08-19 05:31:27 |   스모크 통과
2026-08-19 05:31:27 | START ro-only / r1
2026-08-19 05:54:58 | END   ro-only / r1 (rc=0, 1411s)
2026-08-19 05:54:58 | START ro-only / r2
2026-08-19 06:15:52 | END   ro-only / r2 (rc=0, 1254s)
2026-08-19 06:15:53 | START ro-only / r3
2026-08-19 06:40:29 | END   ro-only / r3 (rc=0, 1476s)
2026-08-19 06:40:29 | --- reza 스모크: $HOME/.local/bin/k8s-mcp-server
2026-08-19 06:40:56 |   스모크 실패 -> 제외
2026-08-19 06:40:56 | === MCP 서버 2차 종료 ===
2026-08-19 08:47:31 | === reza 추가 측정 대기 (다른 런 종료 후 진입) ===
2026-08-19 16:32:33 | START reza / r1
2026-08-19 19:02:16 | END   reza / r1 (rc=0, 8983s)
2026-08-19 19:02:16 | START reza / r2
2026-08-19 22:11:24 | END   reza / r2 (rc=0, 11348s)
2026-08-19 22:11:24 | START reza / r3
2026-08-20 01:32:26 | END   reza / r3 (rc=0, 12062s)
2026-08-20 01:32:26 | === reza 추가 측정 종료 ===
