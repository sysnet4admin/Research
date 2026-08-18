"""두 방언이 스펙대로 구성되는지 검사한다.

이 하네스의 결과가 의미를 가지려면 A가 진짜 2025-11-25처럼, B가 진짜 2026-07-28처럼
말해야 한다. 방언 구성이 틀리면 측정값 전체가 무효라서, 클러스터 없이 돌릴 수 있는
이 검사를 CI에 둔다.

실행: python -m pytest tests/ -q
"""

import json
import pathlib
import sys

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "harness"))

import capture  # noqa: E402
import loadgen  # noqa: E402


class FakeResp:
    """httpx.Response 대역. parse_body/body_of 가 보는 부분만 흉내낸다."""

    def __init__(self, text, ctype="application/json", status=200, headers=None):
        self.text = text
        self.status_code = status
        self.headers = dict(headers or {})
        self.headers.setdefault("content-type", ctype)

    def json(self):
        return json.loads(self.text)


# ---- 방언 A: 2025-11-25 세션 ----


def test_a_는_세션_전에는_세션_헤더를_안_보낸다():
    w = loadgen.WorkerA(None, "http://x/mcp", loadgen.Stats(), "echo", 0)
    assert "Mcp-Session-Id" not in w._headers(with_session=False)


def test_a_는_세션을_받으면_헤더에_싣는다():
    w = loadgen.WorkerA(None, "http://x/mcp", loadgen.Stats(), "echo", 0)
    w.session = "abc-123"
    assert w._headers()["Mcp-Session-Id"] == "abc-123"


def test_a_는_신_스펙_헤더를_보내지_않는다():
    """구 스펙 서버에 신 스펙 헤더가 섞이면 비교가 성립하지 않는다."""
    w = loadgen.WorkerA(None, "http://x/mcp", loadgen.Stats(), "echo", 0)
    w.session = "abc-123"
    h = w._headers()
    for forbidden in ("MCP-Protocol-Version", "Mcp-Method", "Mcp-Name"):
        assert forbidden not in h


# ---- 방언 B: 2026-07-28 스테이트리스 ----


def test_b_는_필수_헤더_3종을_보낸다():
    w = loadgen.WorkerB(None, "http://x/mcp", loadgen.Stats(), "echo", 0)
    h = w._headers("tools/call", "echo")
    assert h["MCP-Protocol-Version"] == "2026-07-28"
    assert h["Mcp-Method"] == "tools/call"
    assert h["Mcp-Name"] == "echo"


def test_b_는_세션_헤더를_보내지_않는다():
    w = loadgen.WorkerB(None, "http://x/mcp", loadgen.Stats(), "echo", 0)
    assert "Mcp-Session-Id" not in w._headers("tools/call", "echo")


def test_b_의_meta_키는_스펙_네임스페이스를_쓴다():
    meta = loadgen.WorkerB.META
    assert meta["io.modelcontextprotocol/protocolVersion"] == "2026-07-28"
    assert "io.modelcontextprotocol/clientInfo" in meta
    assert "io.modelcontextprotocol/clientCapabilities" in meta
    # 네임스페이스 없는 키가 섞이면 서버가 무시하거나 거절한다
    assert all(k.startswith("io.modelcontextprotocol/") for k in meta)


def test_두_방언의_프로토콜_버전이_서로_다르다():
    """A와 B가 같은 버전을 말하면 이 연구의 변수가 사라진다."""
    assert loadgen.PROTO_A != loadgen.PROTO_B
    assert capture.PROTO_A == loadgen.PROTO_A
    assert capture.PROTO_B == loadgen.PROTO_B


# ---- 응답 해석 ----


def test_sse_응답에서_결과를_뽑는다():
    body = FakeResp(
        'event: message\ndata: {"jsonrpc":"2.0","id":1,"result":{"content":[]}}\n\n',
        ctype="text/event-stream",
    )
    assert loadgen.parse_body(body)["id"] == 1


def test_sse에_결과가_없으면_None():
    body = FakeResp("event: ping\ndata: {\"note\":\"keepalive\"}\n\n",
                    ctype="text/event-stream")
    assert loadgen.parse_body(body) is None


def test_json_응답을_그대로_읽는다():
    assert loadgen.parse_body(FakeResp('{"result":{"ok":true}}'))["result"]["ok"] is True


def test_망가진_본문은_None():
    assert loadgen.parse_body(FakeResp("not json at all")) is None


# ---- 백분위 ----


@pytest.mark.parametrize("p,expected", [(0, 1), (50, 5), (100, 10)])
def test_백분위_경계(p, expected):
    assert loadgen.pctl([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], p) == expected


def test_빈_목록의_백분위는_None():
    assert loadgen.pctl([], 50) is None


# ---- 캡처 렌더링 ----


def test_핸들_추출은_문자열_본문에도_안전하다():
    """서버가 JSON이 아닌 것을 돌려줘도 캡처가 죽지 않아야 한다."""
    assert capture.text_result("Bad Gateway") == ""
    assert capture.text_result(None) == ""


def test_핸들_추출():
    body = {"result": {"content": [{"type": "text", "text": "v0:deadbeef"}]}}
    assert capture.text_result(body) == "v0:deadbeef"


def test_렌더링에_요청과_응답이_모두_들어간다():
    rec = [{
        "label": "B1 tools/call", "note": "no handshake",
        "request": {"method": "POST", "path": "/mcp",
                    "headers": {"Mcp-Method": "tools/call"}, "body": {"id": 1}},
        "response": {"status": 200, "headers": {"content-type": "application/json"},
                     "body": {"result": "ok"}},
    }]
    md = capture.render_md(rec)
    assert "## B1 tools/call" in md
    assert "POST /mcp" in md
    assert "Mcp-Method: tools/call" in md
    assert "HTTP/1.1 200" in md
    # 코드 펜스가 짝이 맞아야 렌더가 깨지지 않는다
    assert md.count("```") % 2 == 0
