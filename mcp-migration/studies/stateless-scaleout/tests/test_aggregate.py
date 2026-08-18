"""발표한 수치를 만들어 내는 집계 규칙을 고정한다.

README와 블로그의 표는 chart.py 의 cell()이 계산한다. 규칙은 두 가지다.
처리량은 반복의 중앙값, 유실은 반복의 합. 이 규칙이 조용히 바뀌면 이미 발표한
수치와 어긋나므로 픽스처로 못 박는다.

실행: python -m pytest tests/ -q
"""

import json
import pathlib
import sys

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "harness"))

import chart  # noqa: E402


def write_run(d, name, rps, sloss=0, hloss=0):
    (d / f"{name}.json").write_text(json.dumps({
        "achieved_rps": rps, "session_loss": sloss, "handle_loss": hloss,
    }))


@pytest.fixture
def runs(tmp_path):
    # 반복 3회. 처리량은 흩어지고 유실은 쌓인다
    write_run(tmp_path, "m1-a-echo-close-r4-rep1", 40.0, sloss=3000)
    write_run(tmp_path, "m1-a-echo-close-r4-rep2", 30.0, sloss=2000)
    write_run(tmp_path, "m1-a-echo-close-r4-rep3", 50.0, sloss=4000)
    return tmp_path


def test_처리량은_중앙값이다(runs):
    rps, _, _, _, _ = chart.cell(str(runs), "m1-a-echo-close-r4")
    assert rps == 40.0  # 평균 40.0과 우연히 같지 않도록 값을 고른다


def test_유실은_반복의_합이다(runs):
    _, sloss, _, _, _ = chart.cell(str(runs), "m1-a-echo-close-r4")
    assert sloss == 9000


def test_다른_셀을_섞어_읽지_않는다(runs):
    """접두사가 겹치는 셀(r4 대 r4-something)을 잘못 빨아들이면 표가 틀어진다."""
    write_run(runs, "m1-a-echo-close-r2-rep1", 999.0, sloss=1)
    rps, sloss, _, _, _ = chart.cell(str(runs), "m1-a-echo-close-r4")
    assert rps == 40.0 and sloss == 9000


def test_kill_보조_파일은_제외한다(runs):
    """m3 셀은 rep 파일 옆에 .kill.json 을 남긴다. 이것이 섞이면 안 된다."""
    (runs / "m1-a-echo-close-r4-rep4.kill.json").write_text(json.dumps({
        "achieved_rps": 0.0, "session_loss": 0, "handle_loss": 0,
    }))
    rps, sloss, _, _, _ = chart.cell(str(runs), "m1-a-echo-close-r4")
    assert rps == 40.0 and sloss == 9000


def test_범위도_함께_낸다(runs):
    """cell은 중앙값만이 아니라 최소와 최대를 함께 낸다. 구 스펙 셀은 회차
    편차가 커서 발행문에 범위를 적기 때문이다."""
    _, _, _, lo, hi = chart.cell(str(runs), "m1-a-echo-close-r4")
    assert (lo, hi) == (30.0, 50.0)


def test_짝수_반복은_가운데_두_값의_평균(runs):
    write_run(runs, "m1-a-echo-close-r4-rep4", 60.0, sloss=1000)
    rps, sloss, _, _, _ = chart.cell(str(runs), "m1-a-echo-close-r4")
    assert rps == 45.0  # 40, 50 의 평균
    assert sloss == 10000


def test_발표한_셀을_실제_데이터로_재계산한다():
    """정본 실행 디렉토리가 있으면 README 표의 값과 맞는지 확인한다."""
    runs = pathlib.Path(__file__).resolve().parents[1] / "runs" / "main-2026-08-06b"
    if not runs.exists():
        pytest.skip("정본 실행 데이터 없음 (runs/ 는 git 밖)")
    rps, sloss, _, _, _ = chart.cell(str(runs), "m1-a-echo-close-r4")
    assert round(rps, 1) == 38.3
    assert sloss == 8695
    rps, _, hloss, _, _ = chart.cell(str(runs), "m2-b-mem")
    assert round(rps, 1) == 51.2
    assert hloss == 4461
