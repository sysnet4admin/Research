# ext_proc 인자 통제 서버 (Go, Envoy ext_proc v3)

agentgateway `traffic.extProc`(requestBodyMode Buffered)로 MCP 본문을 받아
`tools/call get-sum`은 `a == 1`일 때만 통과시키고 아니면 403(ImmediateResponse)을
돌려준다. README 한계 절의 "extAuthz와 extProc 미검증"을 닫는 용도(2026-09-07 작성,
아직 클러스터 투입 전).

빌드(클러스터 노드가 VirtualBox ARM64라 linux/arm64 정적 빌드):

```
cd agentgateway-study/k8s/extproc
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags='-s -w' -o extproc-linux-arm64 .
```

배포 안(미구현): emptyDir 파드가 `/work/extproc`가 생길 때까지 기다렸다가 실행하고
`kubectl cp`로 바이너리를 넣는다. 이미지 빌드 없이 재현하기 위한 방식이다.
바이너리(13MB)는 커밋하지 않는다.

## 러너와 배포

`harness/rv_ext.sh`가 `k8s/extproc/extproc.yaml`을 적용하고 파드가 Ready가 되면
`kubectl cp`로 이 바이너리를 `/work/extproc`에 넣는다. 컨테이너는 파일이 생길
때까지 기다렸다 실행한다. 바이너리는 커밋하지 않으므로 러너 전에 위 빌드 명령을
한 번 돌려 둔다.
