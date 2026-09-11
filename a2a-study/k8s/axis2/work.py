"""세 구현이 공유하는 작업 함수. 이 파일 하나를 세 서버가 모두 import 한다.

축 2의 전제가 "같은 작업"이라는 것이므로, 프로토콜만 다르고 계산은 글자 하나까지
같아야 한다. 그래서 문자열 조립까지 여기서 끝낸다.

[축 2 본측정 델타] 시나리오 2를 위해 오래 걸리는 형태를 더했다. 결과 문자열은
짧은 것과 같고 걸리는 시간만 다르다. 세 구현이 같은 시간을 쓰게 하려는 것이다.
"""
import time


def work(text: str) -> str:
    """짧은 작업. 입력을 받아 정해진 형식의 문자열을 돌려준다."""
    return f"processed:{text}:{len(text)}"


def work_slow(text: str, seconds: float) -> str:
    """오래 걸리는 작업(동기). 결과는 work()와 같다."""
    time.sleep(seconds)
    return work(text)


async def work_slow_async(text: str, seconds: float) -> str:
    """오래 걸리는 작업(비동기). asyncio 서버가 이벤트 루프를 막지 않게 한다."""
    import asyncio

    await asyncio.sleep(seconds)
    return work(text)
