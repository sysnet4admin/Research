# 그림과 로고

발행용 SVG는 `harness/chart.py`가 만든다. 수치는 `RESULTS.md`에서 옮긴 고정값이라
`runs/`를 읽지 않는다.

```sh
python3 harness/chart.py <kind> <lang> > figures/<kind>-<lang>.svg
```

`kind`는 `arch`, `list-empty`, `path-cost`, `scale`, `rejection` 다섯이고 `lang`은
`ko`와 `en`이다.

## 만든 뒤에는 검사한다

```sh
python3 harness/check_figures.py
```

글자가 상자를 넘치거나 화면 밖으로 나가는지 본다. 검출이 있으면 비0으로 끝난다.
손으로 렌더링해 눈으로 찾다가 영문판 한 곳을 놓친 적이 있어 만들었다.

검사 항목은 셋이다. 글자가 상자를 넘치는가, 화면 밖으로 나가는가, 가로로 치우쳤는가.
마지막 것은 라벨을 계산에 넣지 않아 거부 그림이 135px 치우쳐 있던 것을 눈으로 못 잡고
넘긴 뒤에 넣었다.

높이는 `chart.py`의 `fit()`이 내용에 맞춰 다시 계산하므로 그림마다 아래 여백이
`BOTTOM_PAD`(22px)로 같다. 함수 안에서 캔버스 높이를 직접 정하지 않는다.

## 밑줄로 시작하는 파일은 로고 원본이다

그림 안에 인라인으로 들어가므로 발행 시 따로 올리지 않는다.

| 파일 | 출처 | 라이선스 |
|---|---|---|
| `_ar-horizontal-primary.svg` | `theagentrouter/agent-router` 의 `site/static/img/brand/` | Apache 2.0 |
| `_envoy-icon-color.svg` | 같은 저장소의 같은 경로 | Apache 2.0 |
| `_agentgateway-logo.svg` | agentgateway 저장소 `ui/public/logo.svg` (agentgateway-study에서 가져옴) | Apache 2.0 |

Agent Router 이름은 상표 정책이 정확한 형태를 요구하므로 로고 대신 글자로 적을
때도 "Agent Router" 두 단어로 쓴다.
